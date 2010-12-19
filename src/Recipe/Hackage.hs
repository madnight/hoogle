
module Recipe.Hackage(makePlatform, makeDefault, makePackage, makeAll) where

import Recipe.Type
import Recipe.General
import General.Base
import General.System
import General.Util
import General.Web


-- FIXME: This is a list of hack
avoid = words "ghc-prim integer integer-simple integer-gmp rts ghc Win32"


makePlatform :: ([Name] -> IO ()) -> IO ()
makePlatform make = do
    xs <- listPlatform
    forM_ xs $ \(name,ver) -> do
        v2 <- version cabals name
        when (ver /= v2) $ putStrLn $ "Warning: Version mismatch for " ++ name ++ " (platform=" ++ ver ++ ", cabal=" ++ v2 ++ ")"
    combine make "platform" (map fst xs) False


makeAll :: ([Name] -> IO ()) -> IO ()
makeAll make = do
    xs <- listing haddocks
    make xs


-- create a database containing an entry for each package in hackage
makePackage :: IO ()
makePackage = do
    xs <- listing cabals
    xs <- forM xs $ \name -> do
        ver <- version cabals name
        let file = cabals </> name </> ver </> name <.> "cabal"
        src <- readCabal file
        return $ [""] ++ zipWith (++) ("-- | " : repeat "--   ") (cabalDescription src) ++
                 ["--","-- Version " ++ ver, "@package " ++ name]
    writeFile "package.txt" $ unlines $ concat xs
    convert noDeps "package"


makeDefault :: ([Name] -> IO ()) -> [FilePath] -> Name -> IO ()
makeDefault make local name = do
    b1 <- doesDirectoryExist $ cabals </> name
    b2 <- doesDirectoryExist $ haddocks </> name
    if not b1 || not b2 then
        putError $ "Error: " ++ name ++ " couldn't find both Cabal and Haddock inputs"
     else do
        vc <- version cabals name
        vh <- version haddocks name
        when (vc /= vh) $ putStrLn $ "Warning: Version mismatch for " ++ name ++ " (cabal=" ++ vc ++ ", haddock=" ++ vh ++ ")"
        let had = haddocks </> name </> vh </> name <.> "txt"
            cab = cabals </> name </> vc </> name <.> "cabal"
        h <- openFile had ReadMode
        sz <- hFileSize h
        hClose h
        if sz == 0 then
            putError $ "Error: " ++ name ++ " has no haddock output"
         else do
            had <- readFile' had
            cab <- readCabal cab
            loc <- findLocal local name
            writeFile (name <.> "txt") $ unlines $
                ["@depends " ++ a | a <- cabalDepends cab \\ (name:avoid)] ++
                (maybe id haddockPackageUrl loc) (haddockHacks $ lines had)
            convert make name


-- try and find a local filepath
findLocal :: [FilePath] -> Name -> IO (Maybe URL)
findLocal paths name = fmap (listToMaybe . concat . concat) $ forM paths $ \p -> do
    xs <- getDirectoryContents p
    xs <- return [p </> x | x <- reverse $ sort xs, name == fst (rbreak (== '-') x)] -- make sure highest version comes first
    forM xs $ \x -> do
        b <- doesDirectoryExist $ x </> "html"
        x <- return $ if b then x </> "html" else x
        b <- doesFileExist $ x </> "doc-index.html"
        return [filePathToURL $ x </> "index.html" | b]


---------------------------------------------------------------------
-- READ PLATFORM

listPlatform :: IO [(Name,String)]
listPlatform = do
    src <- readFile platform
    let xs = takeWhile (not . isPrefixOf "build-tools:" . ltrim) $
             dropWhile (not . isPrefixOf "build-depends:" . ltrim) $
             lines src
    return [(name, takeWhile (\x -> x == '.' || isDigit x) $ drop 1 b)
           | x <- xs, (a,_:b) <- [break (== '=') x], let name = trim $ dropWhile (== '-') $ trim a
           , name `notElem` words "Cabal hpc Win32"]


---------------------------------------------------------------------
-- HADDOCK HACKS

-- Eliminate @version
-- Change :*: to (:*:), Haddock bug
-- Change !!Int to !Int, Haddock bug
-- Change instance [overlap ok] to instance, Haddock bug
-- Change instance [incoherent] to instance, Haddock bug
-- Change !Int to Int, HSE bug

haddockHacks :: [String] -> [String]
haddockHacks = map (unwords . map f . words) . filter (not . isPrefixOf "@version ")
    where
        f "::" = "::"
        f (':':xs) = "(:" ++ xs ++ ")"
        f ('!':'!':x:xs) | isAlpha x = xs
        f ('!':x:xs) | isAlpha x || x `elem` "[(" = x:xs
        f x | x `elem` ["[overlap","ok]","[incoherent]"] = ""
        f x = x


haddockPackageUrl :: URL -> [String] -> [String]
haddockPackageUrl x = concatMap f
    where f y | "@package " `isPrefixOf` y = ["@url " ++ x, y]
              | otherwise = [y]
