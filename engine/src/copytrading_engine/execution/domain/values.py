from decimal import Decimal
from typing import Annotated, Literal, NewType

from pydantic import BaseModel, ConfigDict, Field

Money = Annotated[Decimal, Field(allow_inf_nan=False)]
Positive = Annotated[Money, Field(gt=0)]
Quantity = Annotated[Money, Field(ge=0)]
Identifier = Annotated[str, Field(min_length=1)]
# The broker's own number for an account, which a ledger records to stay bound to one broker
# account. The app names accounts separately (the account's folder, such as "primary"); the two
# are different values and must never be compared with each other.
BrokerAccountNumber = NewType("BrokerAccountNumber", str)
BrokerAccountId = Annotated[BrokerAccountNumber, Field(min_length=1)]
Side = Literal["buy", "sell"]


class Value(BaseModel):
    model_config = ConfigDict(frozen=True, extra="forbid", strict=True, hide_input_in_errors=True)
