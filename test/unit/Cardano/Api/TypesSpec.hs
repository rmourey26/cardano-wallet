{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}

module Cardano.Api.TypesSpec (spec) where

import Prelude

import Cardano.Api.Types
    ( Amount (..)
    , MeasuredIn (..)
    , Percentage (..)
    , Wallet (..)
    , WalletAddressPoolGap (..)
    , WalletBalance (..)
    , WalletDelegation (..)
    , WalletId (..)
    , WalletName (..)
    , WalletPassphraseInfo (..)
    , WalletState (..)
    , mkWalletName
    , walletNameMaxLength
    , walletNameMinLength
    )
import Control.Monad
    ( replicateM )
import Data.Aeson
    ( FromJSON, ToJSON, decode, eitherDecode, encode )
import Data.ByteString.Lazy
    ( ByteString )
import Data.Either
    ( fromRight, isRight, rights )
import Data.Word
    ( Word32, Word8 )
import GHC.Generics
    ( Generic )
import Test.Hspec
    ( Expectation, Spec, describe, it, shouldBe, shouldSatisfy )
import Test.QuickCheck
    ( Arbitrary (..)
    , arbitraryBoundedEnum
    , arbitraryPrintableChar
    , choose
    , oneof
    , property
    )
import Test.QuickCheck.Arbitrary.Generic
    ( genericArbitrary, genericShrink )
import Test.QuickCheck.Instances.Time
    ()
import Text.RawString.QQ
    ( r )

import qualified Data.Text as T
import qualified Data.UUID.Types as UUID


spec :: Spec
spec = do
    describe "can perform basic JSON deserialization" $
        it "Wallet" $
            (eitherDecode exampleWallet :: Either String Wallet)
                `shouldSatisfy` isRight
    describe "can perform roundtrip JSON serialization & deserialization" $ do
        it "Wallet" $
            property $ \a -> canRoundTrip (a :: Wallet)
        it "WalletAddressPoolGap" $
            property $ \a -> canRoundTrip (a :: WalletAddressPoolGap)
        it "WalletBalance" $
            property $ \a -> canRoundTrip (a :: WalletBalance)
        it "WalletDelegation" $
            property $ \a -> canRoundTrip (a :: WalletDelegation)
        it "WalletId" $
            property $ \a -> canRoundTrip (a :: WalletId)
        it "WalletName" $
            property $ \a -> canRoundTrip (a :: WalletName)
        it "WalletPassphraseInfo" $
            property $ \a -> canRoundTrip (a :: WalletPassphraseInfo)
        it "WalletState" $
            property $ \a -> canRoundTrip (a :: WalletState)

canRoundTrip :: Eq a => FromJSON a => ToJSON a => Show a => a -> Expectation
canRoundTrip a = decode (encode a) `shouldBe` Just a

exampleWallet :: ByteString
exampleWallet = [r|
    { "id" : "00000000-0000-0000-0000-000000000000"
    , "name" : "example wallet"
    , "address_pool_gap" : 50
    , "delegation" : { "status" : "not_delegating" }
    , "passphrase" : { "last_updated_at" : "1864-05-02T22:19:08.077666613986Z" }
    , "state" :
        { "status" : "restoring"
        , "progress" :  { "quantity" : 100, "unit" : "percent" } }
    , "balance" :
        { "total"     : { "quantity" : 100, "unit" : "lovelace" }
        , "available" : { "quantity" : 100, "unit" : "lovelace" } } } |]


{-------------------------------------------------------------------------------
                              Arbitrary Instances
-------------------------------------------------------------------------------}

instance Arbitrary Amount where
    shrink (Amount 0) = []
    shrink _ = [Amount 0]
    arbitrary = Amount . fromIntegral <$> (arbitrary @Word8)

instance Arbitrary Percentage where
    arbitrary = Percentage <$> choose (0, 100)

instance Arbitrary Wallet where
    arbitrary = genericArbitrary
    shrink = genericShrink

instance Arbitrary WalletAddressPoolGap where
    arbitrary = arbitraryBoundedEnum

instance Arbitrary WalletBalance where
    arbitrary = genericArbitrary
    shrink = genericShrink

instance Arbitrary WalletDelegation where
    shrink NotDelegating = []
    shrink _ = [NotDelegating]
    arbitrary = oneof
        [ pure NotDelegating
        , Delegating . uuidFromWords <$> arbitrary
        ]

instance Arbitrary WalletId where
    arbitrary = WalletId . uuidFromWords <$> arbitrary

uuidFromWords :: (Word32, Word32, Word32, Word32) -> UUID.UUID
uuidFromWords (a, b, c, d) = UUID.fromWords a b c d

instance Arbitrary WalletName where
    arbitrary = do
        nameLength <- choose (walletNameMinLength, walletNameMaxLength)
        fromRight (error "Unable to create arbitrary WalletName")
            . mkWalletName
            . T.pack <$> replicateM nameLength arbitraryPrintableChar
    shrink =
        rights
            . fmap (mkWalletName . T.pack)
            . shrink
            . T.unpack
            . getWalletName

instance Arbitrary WalletPassphraseInfo where
    arbitrary = genericArbitrary
    shrink = genericShrink

instance Arbitrary WalletState where
    arbitrary = genericArbitrary
    shrink = genericShrink

instance (Arbitrary a, Generic a) => Arbitrary (MeasuredIn u a) where
    shrink = genericShrink
    arbitrary = MeasuredIn <$> arbitrary
