{-# LANGUAGE CPP       #-}
{-# LANGUAGE DataKinds #-}

module Main where

#if __GLASGOW_HASKELL__ <= 708
import Control.Applicative
#endif

import Control.Concurrent (forkIO, killThread, threadDelay)
import Control.Monad (forever)
import Eff
import Data.IORef

import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.QuickCheck

import Tests.Coroutine
import Tests.Exception
import Tests.NonDetEff
import Tests.Reader
import Tests.State

import qualified Data.List

--------------------------------------------------------------------------------
                           -- Pure Tests --
--------------------------------------------------------------------------------
addInEff :: Int -> Int -> Int
addInEff x y = run ((+) <$> pure x <*> pure y)

pureTests :: TestTree
pureTests = testGroup "Pure Eff tests"
  [ testProperty "Pure run just works: (+)"
      (\x y -> addInEff x y == x + y)
  ]

--------------------------------------------------------------------------------
                        -- Coroutine Tests --
--------------------------------------------------------------------------------

-- | Counts number of consecutive pairs of odd elements at beginning of a list.
countOddDuoPrefix :: [Int] -> Int
countOddDuoPrefix list = count list 0
  where
    count (i1:i2:is) n = if even i1 && even i2 then n else count is (n+1)
    count _ n = n

coroutineTests :: TestTree
coroutineTests = testGroup "Coroutine Eff tests"
  [ testProperty "Counting consecutive pairs of odds"
      (\list -> runTestCoroutine list == countOddDuoPrefix list)
  ]

--------------------------------------------------------------------------------
                        -- Exception Tests --
--------------------------------------------------------------------------------
exceptionTests :: TestTree
exceptionTests = testGroup "Exception Eff tests"
  [ testProperty "Exc takes precedence" (\x y -> testExceptionTakesPriority x y == Left y)
  , testCase "uncaught: runState (runError t)" $
      ter1 @?= (Left "exc", 2)
  , testCase "uncaught: runError (runState t)" $
      ter2 @?= Left "exc"
  , testCase "caught: runState (runError t)" $
      ter3 @?= (Right "exc", 2)
  , testCase "caught: runError (runState t)" $
      ter4 @?= Right ("exc", 2)
  , testCase "success: runReader (runErrBig t)" (ex2rr @?= Right 5)
  , testCase "uncaught: runReader (runErrBig t)" $
      ex2rr1 @?= Left (TooBig 7)
  , testCase "uncaught: runErrBig (runReader t)" $
      ex2rr2 @?= Left (TooBig 7)
  ]

--------------------------------------------------------------------------------
                 -- Nondeterministic Effect Tests --
--------------------------------------------------------------------------------
-- https://wiki.haskell.org/Prime_numbers
primesTo :: Int -> [Int]
primesTo m = sieve [2..m]       {- (\\) is set-difference for unordered lists -}
  where
    sieve (x:xs) = x : sieve (xs Data.List.\\ [x,x+x..m])
    sieve [] = []

nonDetEffTests :: TestTree
nonDetEffTests = testGroup "NonDetEff tests"
  [ testProperty "Primes in 2..n generated by ifte"
      (\n' -> let n = abs n' in testIfte [2..n] == primesTo n)
  ]

--------------------------------------------------------------------------------
                      -- Reader Effect Tests --
--------------------------------------------------------------------------------
readerTests :: TestTree
readerTests = testGroup "Reader tests"
  [ testProperty "Reader passes along environment: n + x"
    (\n x -> testReader n x == n + x)
  , testProperty "Multiple readers work"
    (\f n -> testMultiReader f n == ((f + 2.0) + fromIntegral (n + 1)))
  , testProperty "Local injects into env"
    (\env inc -> testLocal env inc == 2*(env+1) + inc)
  , testProperty "We can effmap Readers: n + x"
      $ \n x -> testEffmapReader n x == show n ++ show x
  ]

--------------------------------------------------------------------------------
                     -- State[RW] Effect Tests --
--------------------------------------------------------------------------------
stateTests :: TestTree
stateTests = testGroup "State tests"
  [ testProperty "get after put n yields (n,n)" (\n -> testPutGet n 0 == (n,n))
  , testProperty "Final put determines stored state" $
    \p1 p2 start -> testPutGetPutGetPlus p1 p2 start == (p1+p2, p2)
  , testProperty "If only getting, start state determines outcome" $
    \start -> testGetStart start == (start,start)
  , testProperty "testInveffmap: inveffmap works over state"
      $ \n -> testInveffmap n == (show (fst n) ++ snd n)
  ]

--------------------------------------------------------------------------------
                           -- Loop Check --
--------------------------------------------------------------------------------
loop :: IORef Int -> Eff '[IO] ()
loop ref = forever $ send $ modifyIORef' ref succ

testLoop :: IO Int
testLoop = do
  ref <- newIORef 0
  tid <- forkIO $ runM $ loop ref
  threadDelay $ 10^(6 :: Int) * 2
  killThread tid
  readIORef ref

loopTests :: Int -> TestTree
loopTests n =
  testGroup "Loop tests" [ testProperty "any number of loops" (\() -> n > 0)]

--------------------------------------------------------------------------------
                             -- Runner --
--------------------------------------------------------------------------------
main :: IO ()
main = do
  n <- testLoop
  defaultMain $ testGroup "Tests"
    [ pureTests
    , coroutineTests
    , exceptionTests
    , loopTests n
    , nonDetEffTests
    , readerTests
    , stateTests
    ]
