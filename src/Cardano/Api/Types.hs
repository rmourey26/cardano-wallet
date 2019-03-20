{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}

module Cardano.Api.Types
    (
    -- * API Types
      Amount(..)
    , Percentage(..)
    , Wallet(..)
    , WalletAddressPoolGap(..)
    , WalletBalance(..)
    , WalletDelegation(..)
    , WalletName(..)
    , WalletId (..)
    , WalletPassphraseInfo(..)
    , WalletState(..)
    , mkWalletName
    , walletNameMinLength
    , walletNameMaxLength

    -- * Polymorphic Types
    , MeasuredIn(..)
    ) where

import Prelude

import Cardano.Wallet.AddressDiscovery
    ( AddressPoolGap, getAddressPoolGap, mkAddressPoolGap )
import Data.Aeson
    ( FromJSON (..)
    , SumEncoding (..)
    , ToJSON (..)
    , Value (String)
    , camelTo2
    , constructorTagModifier
    , fieldLabelModifier
    , genericParseJSON
    , genericToJSON
    , object
    , omitNothingFields
    , sumEncoding
    , tagSingleConstructors
    , withObject
    , (.:)
    , (.=)
    )
import Data.Proxy
    ( Proxy (..) )
import Data.Text
    ( Text )
import Data.Time.Clock
    ( UTCTime )
import Data.UUID.Types
    ( UUID )
import GHC.Generics
    ( Generic )
import GHC.TypeLits
    ( KnownSymbol, Symbol, symbolVal )
import Numeric.Natural
    ( Natural )

import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Types as Aeson
import qualified Data.Text as T


{-------------------------------------------------------------------------------
                                  API Types
-------------------------------------------------------------------------------}

newtype Amount = Amount Natural
    deriving stock (Generic, Show, Ord, Eq)
    deriving newtype (ToJSON, FromJSON)

newtype Percentage = Percentage Int
    deriving stock (Eq, Generic, Ord, Show)
    deriving newtype (ToJSON)

data PercentageError
    = PercentageOutOfBoundsError
    deriving (Show)

instance Bounded Percentage where
    minBound = Percentage 0
    maxBound = Percentage 100

instance FromJSON Percentage where
    parseJSON x = do
        percent <- parseJSON x
        eitherToParser (mkPercentage @Int percent)

mkPercentage :: Integral i => i -> Either PercentageError Percentage
mkPercentage i
    | j < minBound = Left PercentageOutOfBoundsError
    | j > maxBound = Left PercentageOutOfBoundsError
    | otherwise = pure j
  where
    j = Percentage (fromIntegral i)


data Wallet = Wallet
    { _id :: !WalletId
    , _addressPoolGap :: !WalletAddressPoolGap
    , _balance :: !WalletBalance
    , _delegation :: !WalletDelegation
    , _name :: !WalletName
    , _passphrase :: !WalletPassphraseInfo
    , _state :: !WalletState
    } deriving (Eq, Generic, Show)

instance FromJSON Wallet where
    parseJSON = genericParseJSON defaultRecordTypeOptions
instance ToJSON Wallet where
    toJSON = genericToJSON defaultRecordTypeOptions

newtype WalletAddressPoolGap = WalletAddressPoolGap
    { getWalletAddressPoolGap :: AddressPoolGap }
    deriving stock (Generic, Show)
    deriving newtype (Bounded, Enum, Eq, Ord)

instance FromJSON WalletAddressPoolGap where
    parseJSON x = do
        gap <- parseJSON x
        WalletAddressPoolGap <$> eitherToParser (mkAddressPoolGap gap)
instance ToJSON WalletAddressPoolGap where
    toJSON = toJSON . getAddressPoolGap . getWalletAddressPoolGap


data WalletBalance = WalletBalance
    { _available :: !(MeasuredIn "lovelace" Amount)
    , _total :: !(MeasuredIn "lovelace" Amount)
    } deriving (Eq, Generic, Show)

instance FromJSON WalletBalance where
    parseJSON = genericParseJSON defaultRecordTypeOptions
instance ToJSON WalletBalance where
    toJSON = genericToJSON defaultRecordTypeOptions


-- | Wallet Delegation representation, can be serialized to and from JSON as
-- follows:
--
-- >>> Aeson.encode NotDelegating
-- {"status":"not_delegating"}
--
-- >>> Aeson.encode $ Delegating poolId
-- {"status":"delegating","target": "27522fe5-262e-42a5-8ccb-cef884ea2ba0"}
data WalletDelegation
    = NotDelegating
    | Delegating !UUID
    deriving (Eq, Generic, Show)

instance FromJSON WalletDelegation where
    parseJSON = genericParseJSON walletDelegationOptions
instance ToJSON WalletDelegation where
    toJSON = genericToJSON walletDelegationOptions

walletDelegationOptions :: Aeson.Options
walletDelegationOptions = taggedSumTypeOptions $ TaggedObjectOptions
    { _tagFieldName = "status"
    , _contentsFieldName = "target"
    }


newtype WalletId = WalletId
    { _uuid :: UUID }
    deriving stock (Eq, Show)
    deriving newtype (FromJSON, ToJSON)


newtype WalletName = WalletName
    { getWalletName :: Text }
    deriving stock (Eq, Generic, Show)
    deriving newtype (ToJSON)

data WalletNameError
    = WalletNameTooShortError
    | WalletNameTooLongError
    deriving Show

instance FromJSON WalletName where
    parseJSON x = eitherToParser . mkWalletName =<< parseJSON x

walletNameMinLength :: Int
walletNameMinLength = 1

walletNameMaxLength :: Int
walletNameMaxLength = 255

mkWalletName :: Text -> Either WalletNameError WalletName
mkWalletName n
    | T.length n < walletNameMinLength = Left WalletNameTooShortError
    | T.length n > walletNameMaxLength = Left WalletNameTooLongError
    | otherwise = Right $ WalletName n


newtype WalletPassphraseInfo = WalletPassphraseInfo
    { _lastUpdatedAt :: UTCTime
    } deriving (Eq, Generic, Show)

instance FromJSON WalletPassphraseInfo where
    parseJSON = genericParseJSON defaultRecordTypeOptions
instance ToJSON WalletPassphraseInfo where
    toJSON = genericToJSON defaultRecordTypeOptions


-- | A Wallet State representation in the API. It can be serialized to and from
-- JSON as follows:
--
-- >>> Aeson.encode Ready
-- {"status":"ready"}
--
-- >>> Aeson.encode $ Restoring (Percentage 14)
-- {"status":"restoring","progress":{"quantity":14,"unit":"percent"}}
data WalletState
    = Ready
    | Restoring !(MeasuredIn "percent" Percentage)
    deriving (Eq, Generic, Show)

instance FromJSON WalletState where
    parseJSON = genericParseJSON walletStateOptions
instance ToJSON WalletState where
    toJSON = genericToJSON walletStateOptions

walletStateOptions :: Aeson.Options
walletStateOptions = taggedSumTypeOptions $ TaggedObjectOptions
    { _tagFieldName = "status"
    , _contentsFieldName = "progress"
    }


{-------------------------------------------------------------------------------
                              Polymorphic Types
-------------------------------------------------------------------------------}

-- | Represent measurable things with simpler underlying types. We probably
-- want to move that as a separate module in the wallet primitives.
newtype MeasuredIn (u :: Symbol) a = MeasuredIn a
    deriving (Generic, Show, Eq)

instance (KnownSymbol u, ToJSON a) => ToJSON (MeasuredIn u a) where
    toJSON (MeasuredIn a) = object
        [ "unit"     .= symbolVal (Proxy :: Proxy u)
        , "quantity" .= toJSON a
        ]

instance (KnownSymbol u, FromJSON a) => FromJSON (MeasuredIn u a) where
    parseJSON = withObject "MeasuredIn" $ \o -> do
        verifyUnit =<< o .: "unit"
        MeasuredIn <$> o .: "quantity"
      where
        u = symbolVal (Proxy :: Proxy u)
        verifyUnit = \case
            String u' | u' == T.pack u -> pure ()
            _ -> fail $
                "failed to parse quantified value. Expected value in '" <> u
                <> "' (e.g. { \"unit\": \"" <> u <> "\", \"quantity\": ...})"
                <> " but got something else."


{-------------------------------------------------------------------------------
                                Aeson Options
-------------------------------------------------------------------------------}

data TaggedObjectOptions = TaggedObjectOptions
    { _tagFieldName :: String
    , _contentsFieldName :: String
    }

defaultSumTypeOptions :: Aeson.Options
defaultSumTypeOptions = Aeson.defaultOptions
    { constructorTagModifier = camelTo2 '_'
    , tagSingleConstructors = True }

defaultRecordTypeOptions :: Aeson.Options
defaultRecordTypeOptions = Aeson.defaultOptions
    { fieldLabelModifier = camelTo2 '_' . drop 1
    , omitNothingFields = True }

taggedSumTypeOptions :: TaggedObjectOptions -> Aeson.Options
taggedSumTypeOptions opts = defaultSumTypeOptions
    { sumEncoding = TaggedObject (_tagFieldName opts) (_contentsFieldName opts)
    }

{-------------------------------------------------------------------------------
                                   Helpers
-------------------------------------------------------------------------------}

eitherToParser :: Show s => Either s a -> Aeson.Parser a
eitherToParser = either (fail . show) pure
