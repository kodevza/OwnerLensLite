from datetime import datetime, timezone
from decimal import Decimal
from typing import Literal
from uuid import UUID, uuid4

from pydantic import BaseModel, Field, field_validator


class RefundRequest(BaseModel):
    account_id: str = Field(min_length=1, max_length=128, examples=["acc-100042"])
    amount: Decimal = Field(gt=0, max_digits=12, decimal_places=2, examples=[49.90])
    currency: str = Field(min_length=3, max_length=3, examples=["PLN"])
    reason: str = Field(min_length=3, max_length=256, examples=["Summer campaign goodwill refund"])
    campaign_id: str | None = Field(default=None, max_length=128, examples=["SUMMER-2026"])
    payment_reference: str = Field(min_length=1, max_length=128, examples=["pay_20260907_001"])

    @field_validator("currency")
    @classmethod
    def normalize_currency(cls, value: str) -> str:
        return value.upper()


class Adjustment(BaseModel):
    adjustment_id: UUID = Field(default_factory=uuid4)
    account_id: str
    amount: Decimal
    currency: str
    reason: str
    campaign_id: str | None
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    status: Literal["created", "refund_submitted", "refund_failed"] = "created"


class PaymentRefundRequest(BaseModel):
    adjustment_id: UUID
    account_id: str
    payment_reference: str
    amount: Decimal
    currency: str
    reason: str


class PaymentRefundResult(BaseModel):
    refund_id: UUID
    status: Literal["accepted", "settled", "failed"]
    provider_reference: str


class RefundResult(BaseModel):
    adjustment: Adjustment
    payment: PaymentRefundResult


class BdrRequest(BaseModel):
    account_id: str = Field(min_length=1, max_length=128, examples=["acc-100042"])
    amount: Decimal = Field(gt=0, max_digits=12, decimal_places=2, examples=[49.90])
    currency: str = Field(min_length=3, max_length=3, examples=["PLN"])
    reason: str = Field(min_length=3, max_length=256, examples=["Monthly subscription charge"])
    payment_reference: str = Field(min_length=1, max_length=128, examples=["pay_20260907_002"])

    @field_validator("currency")
    @classmethod
    def normalize_currency(cls, value: str) -> str:
        return value.upper()


class Bdr(BaseModel):
    bdr_id: UUID = Field(default_factory=uuid4)
    account_id: str
    amount: Decimal
    currency: str
    reason: str
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    status: Literal["created", "charge_submitted", "charge_failed"] = "created"


class PaymentChargeRequest(BaseModel):
    bdr_id: UUID
    account_id: str
    payment_reference: str
    amount: Decimal
    currency: str
    reason: str


class PaymentChargeResult(BaseModel):
    charge_id: UUID
    status: Literal["accepted", "settled", "failed"]
    provider_reference: str


class BdrResult(BaseModel):
    bdr: Bdr
    payment: PaymentChargeResult
