from uuid import UUID, uuid4

from fastapi import Depends, FastAPI, HTTPException, status

from .auth import require_charge_execute_role, require_refund_execute_role
from .openapi import install_entra_openapi
from .models import ChargeExecutionRequest, ChargeExecutionResult, RefundExecutionRequest, RefundExecutionResult

app = FastAPI(
    title="OwnerLens Demo — Payment Service",
    version="1.0.0",
    description=(
        "Simulated payment service that moves real money. In the OwnerLens demo this is the "
        "only workload with an explicit human owner in Entra ID."
    ),
    docs_url="/docs",
    openapi_url="/openapi.json",
    redoc_url="/redoc",
    contact={"name": "Payments Team — explicit accountable owner"},
)

install_entra_openapi(app)

_refunds: dict[UUID, RefundExecutionResult] = {}
_charges: dict[UUID, ChargeExecutionResult] = {}


@app.get("/health", tags=["Operations"], summary="Liveness check")
async def health() -> dict[str, str]:
    return {"status": "ok", "service": "payment"}


@app.post(
    "/api/v1/refunds/execute",
    response_model=RefundExecutionResult,
    status_code=status.HTTP_201_CREATED,
    tags=["Refunds"],
    summary="Execute a real-money refund",
    description="Requires application role `Refund.Execute`. This simulates the PSP/bank payout boundary.",
)
async def execute_refund(
    request: RefundExecutionRequest,
    _: None = Depends(require_refund_execute_role),
) -> RefundExecutionResult:
    result = RefundExecutionResult(
        provider_reference=f"psp-{uuid4().hex[:16]}",
    )
    _refunds[result.refund_id] = result
    return result


@app.post(
    "/api/v1/charges/execute",
    response_model=ChargeExecutionResult,
    status_code=status.HTTP_201_CREATED,
    tags=["Charges"],
    summary="Execute a charge",
    description="Requires application role `Charge.Execute`. This simulates the PSP/card charge boundary.",
)
async def execute_charge(
    request: ChargeExecutionRequest,
    _: None = Depends(require_charge_execute_role),
) -> ChargeExecutionResult:
    result = ChargeExecutionResult(provider_reference=f"psp-{uuid4().hex[:16]}")
    _charges[result.charge_id] = result
    return result


@app.get(
    "/api/v1/refunds/{refund_id}",
    response_model=RefundExecutionResult,
    tags=["Refunds"],
    summary="Read payment refund state",
)
async def get_refund(
    refund_id: UUID,
    _: None = Depends(require_refund_execute_role),
) -> RefundExecutionResult:
    result = _refunds.get(refund_id)
    if not result:
        raise HTTPException(status_code=404, detail="Refund not found")
    return result
