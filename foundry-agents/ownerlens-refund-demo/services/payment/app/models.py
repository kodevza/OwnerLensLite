from decimal import Decimal
from typing import Literal
from uuid import UUID, uuid4

from pydantic import BaseModel, Field


class RefundExecutionRequest(BaseModel):
    adjustment_id: UUID
    account_id: str = Field(min_length=1, max_length=128)
    payment_reference: str = Field(min_length=1, max_length=128)
    amount: Decimal = Field(gt=0, max_digits=12, decimal_places=2)
    currency: str = Field(min_length=3, max_length=3)
    reason: str = Field(min_length=3, max_length=256)


class RefundExecutionResult(BaseModel):
    refund_id: UUID = Field(default_factory=uuid4)
    status: Literal["accepted", "settled", "failed"] = "settled"
    provider_reference: str


class ChargeExecutionRequest(BaseModel):
    bdr_id: UUID
    account_id: str = Field(min_length=1, max_length=128)
    payment_reference: str = Field(min_length=1, max_length=128)
    amount: Decimal = Field(gt=0, max_digits=12, decimal_places=2)
    currency: str = Field(min_length=3, max_length=3)
    reason: str = Field(min_length=3, max_length=256)


class ChargeExecutionResult(BaseModel):
    charge_id: UUID = Field(default_factory=uuid4)
    status: Literal["accepted", "settled", "failed"] = "settled"
    provider_reference: str
