--------------------------------------------------------------------------------
{-# LANGUAGE OverloadedStrings #-}
import           Data.Monoid (mappend)
import           Hakyll
--import qualified Data.Set as S
--import           Text.Pandoc.Options
--------------------------------------------------------------------------------

{- pandocMathCompiler =
    let mathExtensions = [Ext_tex_math_dollars, Ext_tex_math_double_backslash,
                          Ext_latex_macros]
        defaultExtensions = writerExtensions defaultHakyllWriterOptions
        -- newExtensions = foldr S.insert defaultExtensions mathExtensions
        writerOptions = defaultHakyllWriterOptions {
                          -- writerExtensions = newExtensions,
                          writerHTMLMathMethod = MathJax ""
                        }
    in pandocCompilerWith defaultHakyllReaderOptions writerOptions

customPandocCompiler =
  pandocCompilerWith
    defaultHakyllWriterOptions
      { writerHtml5            = True
      , writerHighlight        = True
      , writerHighlightStyle   = pygments
      , writerHTMLMathMethod   = MathML Nothing
      , writerEmailObfuscation = NoObfuscation
      }  -}

main :: IO ()
main = hakyll $ do
    match "images/*" $ do
        route   idRoute
        compile copyFileCompiler

    match "files/*" $ do
        route   idRoute
        compile copyFileCompiler

    match "css/*" $ do
        route   idRoute
        compile copyFileCompiler  -- compressCssCompiler

    match "scripts/*" $ do
        route   idRoute
        compile copyFileCompiler

    match "LICENSE.md" $ do
        route   idRoute
        compile copyFileCompiler

    match "feed.xml" $ do
        route   idRoute
        compile copyFileCompiler

    match (fromList ["ouca.md", "apoio.md"]) $ do
        route   $ setExtension "html"
        compile $ pandocCompiler
            >>= loadAndApplyTemplate "templates/default.html" defaultContext
            >>= relativizeUrls

    match "posts/*" $ do
        route $ setExtension "html"
        compile $ pandocCompiler
            >>= loadAndApplyTemplate "templates/post.html"    postCtx
            >>= saveSnapshot "content"
            >>= loadAndApplyTemplate "templates/default.html" postCtx
            >>= relativizeUrls

    -- Create RSS feed as well
    create ["rss.xml"] $ do
        route idRoute
        compile $ do
            let feedCtx = postCtx `mappend` bodyField "description"
            posts <- fmap (take 100) . recentFirst =<<
                loadAllSnapshots "posts/*" "content"
            renderRss feedConfiguration feedCtx posts

    create ["episodios.html"] $ do
        route idRoute
        compile $ do
            posts <- recentFirst =<< loadAll "posts/*"
            let archiveCtx =
                    listField "posts" postCtx (return posts) `mappend`
                    constField "title" "episódios"           `mappend`
                    defaultContext

            makeItem ""
                >>= loadAndApplyTemplate "templates/post-list.html" archiveCtx
                >>= loadAndApplyTemplate "templates/default.html" archiveCtx
                >>= relativizeUrls


    match "index.html" $ do
        route idRoute
        compile $ do
            posts <- recentFirst =<< loadAll "posts/*"
            let indexCtx =
                    listField "posts" postCtx (return posts) `mappend`
                    constField "title" "sobre"               `mappend`
                    defaultContext

            getResourceBody
                >>= applyAsTemplate indexCtx
                >>= loadAndApplyTemplate "templates/default.html" indexCtx
                >>= relativizeUrls

    match "templates/*" $ compile templateBodyCompiler


--------------------------------------------------------------------------------
postCtx :: Context String
postCtx =
    dateField "date" "%B %e, %Y" `mappend`
    -- field "file" file <>
    defaultContext


--------------------------------------------------------------------------------
{- customRenderRss :: FeedConfiguration -> Context String -> [Item String] -> Compiler (Item String)
customRenderRss config context items = do
  rssTemplate     <- unsafeCompiler $ readFile "templates/rss.xml"
  rssItemTemplate <- unsafeCompiler $ readFile "templates/rss-item.xml"
  renderRssWithTemplates rssTemplate rssItemTemplate config context items


--------------------------------------------------------------------------------
customRenderAtom :: FeedConfiguration -> Context String -> [Item String] -> Compiler (Item String)
customRenderAtom config context items = do
  atomTemplate     <- unsafeCompiler $ readFile "templates/atom.xml"
  atomItemTemplate <- unsafeCompiler $ readFile "templates/atom-item.xml"
  renderAtomWithTemplates atomTemplate atomItemTemplate config context items


--------------------------------------------------------------------------------
feedCtx :: Context String
feedCtx = mconcat
    [ bodyField "description"
    , Context $ \key -> case key of
        "title" -> unContext (mapContext escapeHtml defaultContext) key
        _       -> unContext mempty key
    , defaultContext
    ]


--------------------------------------------------------------------------------
-- | Abstract function to render any feed.
renderFeed' :: String                  -- ^ Default feed template
           -> String                  -- ^ Default item template
           -> FeedConfiguration       -- ^ Feed configuration
           -> Context String          -- ^ Context for the items
           -> [Item String]           -- ^ Input items
           -> Compiler (Item String)  -- ^ Resulting item
renderFeed' defFeed defItem config itemContext items = do
    feedTpl <- readTemplateFile defFeed
    itemTpl <- readTemplateFile defItem

    protectedItems <- mapM (applyFilter protectCDATA) items
    body <- makeItem =<< applyTemplateList itemTpl itemContext' protectedItems
    applyTemplate feedTpl feedContext body
  where
    applyFilter :: (Monad m,Functor f) => (String -> String) -> f String -> m (f String)
    applyFilter tr str = return $ fmap tr str
    protectCDATA :: String -> String
    protectCDATA = replaceAll "]]>" (const "]]&gt;")

    itemContext' = mconcat
        [ itemContext
        , constField "root" (feedRoot config)
        , constField "authorName"  (feedAuthorName config)
        , constField "authorEmail" (feedAuthorEmail config)
        ]

    feedContext = mconcat
         [ bodyField  "body"
         , constField "title"       (feedTitle config)
         , constField "description" (feedDescription config)
         , constField "authorName"  (feedAuthorName config)
         , constField "authorEmail" (feedAuthorEmail config)
         , constField "root"        (feedRoot config)
         , urlField   "url"
         , fileField   "file"
         , updatedField
         , missingField
         ]

    -- Take the first "updated" field from all items -- this should be the most
    -- recent.
    updatedField = field "updated" $ \_ -> case items of
        []      -> return "Unknown"
        (x : _) -> unContext itemContext' "updated" [] x >>= \cf -> case cf of
            ListField _ _ -> fail "Hakyll.Web.Feed.renderFeed: Internal error"
            StringField s -> return s

    readTemplateFile :: String -> Compiler Template
    readTemplateFile value = pure $ template $ readTemplateElems value


--------------------------------------------------------------------------------
-- | Render an RSS feed with a number of items.
renderRss' :: FeedConfiguration       -- ^ Feed configuration
          -> Context String          -- ^ Item context
          -> [Item String]           -- ^ Feed items
          -> Compiler (Item String)  -- ^ Resulting feed
renderRss' config context = renderFeed
    rssTemplate rssItemTemplate config
    (makeItemContext "%a, %d %b %Y %H:%M:%S UT" context)


--------------------------------------------------------------------------------
-- | Render an Atom feed with a number of items.
renderAtom' :: FeedConfiguration       -- ^ Feed configuration
           -> Context String          -- ^ Item context
           -> [Item String]           -- ^ Feed items
           -> Compiler (Item String)  -- ^ Resulting feed
renderAtom' config context = renderFeed
    atomTemplate atomItemTemplate config
    (makeItemContext "%Y-%m-%dT%H:%M:%SZ" context)
  -}



--------------------------------------------------------------------------------
feedConfiguration :: FeedConfiguration
feedConfiguration = FeedConfiguration
    { feedTitle       = "Ministério da Ciência: episódios"
    , feedDescription = "Feed RSS do podcast"
    , feedAuthorName  = "Caetano Souto Maior"
    , feedAuthorEmail = "caetanosoutomaior@protonmail.com"
    , feedRoot        = "https://ministeriodaciencia.github.io"
    }
