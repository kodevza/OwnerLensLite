from uuid import UUID

from fastapi import Depends, FastAPI, HTTPException, status

from .auth import Caller, require_bdr_create_role, require_refund_request_role
from .openapi import install_entra_openapi
from .models import Bdr, BdrRequest, BdrResult, Adjustment, PaymentChargeRequest, PaymentRefundRequest, RefundRequest, RefundResult
from .payment_client import execute_charge, execute_refund

app = FastAPI(
    title="OwnerLens Demo — Billing Service",
    version="1.0.0",
    description=(
        "Simulated telco-style billing service. Creates a negative financial adjustment "
        "and orchestrates a real-money refund through Payment Service. "
        "Business endpoints are protected by Microsoft Entra ID / Azure App Service Easy Auth."
    ),
    docs_url="/docs",
    openapi_url="/openapi.json",
    redoc_url="/redoc",
    contact={"name": "Billing Platform — technical service context only"},
)

install_entra_openapi(app)

_adjustments: dict[UUID, Adjustment] = {}
_bdrs: dict[UUID, Bdr] = {}


@app.get("/health", tags=["Operations"], summary="Liveness check")
async def health() -> dict[str, str]:
    return {"status": "ok", "service": "billing"}


@app.post(
    "/api/v1/refunds",
    response_model=RefundResult,
    status_code=status.HTTP_201_CREATED,
    tags=["Refunds"],
    summary="Create adjustment and request a refund",
    description=(
        "Creates a negative adjustment on the billing account, then calls Payment Service "
        "using Billing's user-assigned managed identity. Requires app role `Refund.Request`."
    ),
)
async def create_refund(
    request: RefundRequest,
    caller: Caller = Depends(require_refund_request_role),
) -> RefundResult:
    adjustment = Adjustment(
        account_id=request.account_id,
        amount=-request.amount,
        currency=request.currency,
        reason=request.reason,
        campaign_id=request.campaign_id,
    )
    _adjustments[adjustment.adjustment_id] = adjustment

    try:
        payment = await execute_refund(
            PaymentRefundRequest(
                adjustment_id=adjustment.adjustment_id,
                account_id=request.account_id,
                payment_reference=request.payment_reference,
                amount=request.amount,
                currency=request.currency,
                reason=request.reason,
            )
        )
        adjustment.status = "refund_submitted"
    except Exception as exc:  # noqa: BLE001
        adjustment.status = "refund_failed"
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"Adjustment created but Payment Service failed: {exc}",
        ) from exc

    return RefundResult(adjustment=adjustment, payment=payment)


@app.post(
    "/api/v1/bdrs",
    response_model=BdrResult,
    status_code=status.HTTP_201_CREATED,
    tags=["BDRs"],
    summary="Create a BDR and execute a charge",
    description=(
        "Creates a billing debit request (BDR), then calls Payment Service to execute the charge "
        "using Billing's user-assigned managed identity. Requires app role `Charge.Request`."
    ),
)
async def create_bdr(
    request: BdrRequest,
    _: Caller = Depends(require_bdr_create_role),
) -> BdrResult:
    bdr = Bdr(
        account_id=request.account_id,
        amount=request.amount,
        currency=request.currency,
        reason=request.reason,
    )
    _bdrs[bdr.bdr_id] = bdr

    try:
        payment = await execute_charge(
            PaymentChargeRequest(
                bdr_id=bdr.bdr_id,
                account_id=request.account_id,
                payment_reference=request.payment_reference,
                amount=request.amount,
                currency=request.currency,
                reason=request.reason,
            )
        )
        bdr.status = "charge_submitted"
    except Exception as exc:  # noqa: BLE001
        bdr.status = "charge_failed"
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"BDR created but Payment Service failed: {exc}",
        ) from exc

    return BdrResult(bdr=bdr, payment=payment)


@app.get(
    "/api/v1/adjustments/{adjustment_id}",
    response_model=Adjustment,
    tags=["Adjustments"],
    summary="Read an adjustment",
)
async def get_adjustment(
    adjustment_id: UUID,
    _: Caller = Depends(require_refund_request_role),
) -> Adjustment:
    adjustment = _adjustments.get(adjustment_id)
    if not adjustment:
        raise HTTPException(status_code=404, detail="Adjustment not found")
    return adjustment
