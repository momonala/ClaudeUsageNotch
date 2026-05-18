import io
import os
import logging
import zipfile
import asyncio
from datetime import datetime, timezone
from pathlib import Path
from typing import List, Optional

from fastapi import APIRouter, FastAPI, HTTPException
from fastapi.responses import StreamingResponse, RedirectResponse
from dotenv import load_dotenv
from motor.motor_asyncio import AsyncIOMotorClient
from pydantic import BaseModel, ConfigDict, EmailStr, Field
from starlette.middleware.cors import CORSMiddleware

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------
ROOT_DIR = Path(__file__).parent
load_dotenv(ROOT_DIR / ".env")

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)
logger = logging.getLogger("notchy-limit")

mongo_url = os.environ["MONGO_URL"]
client = AsyncIOMotorClient(mongo_url)
db = client[os.environ["DB_NAME"]]

SWIFT_PROJECT_DIR = Path("/app/swift-project/NotchyLimit")
GITHUB_RELEASES_URL = os.environ.get(
    "GITHUB_RELEASES_URL", "https://github.com/notchylimit/notchy-limit/releases"
)
GITHUB_REPO_URL = os.environ.get(
    "GITHUB_REPO_URL", "https://github.com/notchylimit/notchy-limit"
)

app = FastAPI(title="Notchy Limit API", version="0.1.0")
api = APIRouter(prefix="/api")


# ---------------------------------------------------------------------------
# Models
# ---------------------------------------------------------------------------
class WaitlistEntry(BaseModel):
    model_config = ConfigDict(extra="ignore")
    email: EmailStr
    provider: str = Field(default="gemini")


class WaitlistResponse(BaseModel):
    ok: bool
    deduped: bool
    waitlist_count: int


class StatsResponse(BaseModel):
    downloads: int
    waitlist_count: int
    providers: dict
    repo_url: str
    releases_url: str


class FeedbackEntry(BaseModel):
    model_config = ConfigDict(extra="ignore")
    name: Optional[str] = None
    email: Optional[EmailStr] = None
    message: str = Field(min_length=2, max_length=2000)


class HealthResponse(BaseModel):
    ok: bool
    service: str = "notchy-limit-api"
    time: datetime


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
async def ensure_indexes():
    try:
        await db.waitlist.create_index(
            [("email", 1), ("provider", 1)], unique=True, name="uniq_email_provider"
        )
    except Exception as exc:
        logger.warning(f"index ensure failed: {exc}")


def _zip_swift_project() -> bytes:
    """Walk SWIFT_PROJECT_DIR and stream it into an in-memory zip."""
    if not SWIFT_PROJECT_DIR.exists():
        raise FileNotFoundError(f"Swift project dir not found at {SWIFT_PROJECT_DIR}")

    buffer = io.BytesIO()
    excluded_parts = {".git", "build", ".derived-data", "node_modules", "__pycache__"}
    with zipfile.ZipFile(buffer, mode="w", compression=zipfile.ZIP_DEFLATED) as zf:
        for path in SWIFT_PROJECT_DIR.rglob("*"):
            if path.is_dir():
                continue
            if any(part in excluded_parts for part in path.parts):
                continue
            arcname = Path("NotchyLimit") / path.relative_to(SWIFT_PROJECT_DIR)
            zf.write(path, arcname.as_posix())
    buffer.seek(0)
    return buffer.read()


async def _bump_counter(name: str) -> int:
    res = await db.counters.find_one_and_update(
        {"_id": name},
        {"$inc": {"value": 1}},
        upsert=True,
        return_document=True,
    )
    if res is None:
        return 1
    return int(res.get("value", 1))


async def _read_counter(name: str) -> int:
    doc = await db.counters.find_one({"_id": name})
    return int(doc.get("value", 0)) if doc else 0


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------
@api.get("/")
async def index():
    return {"service": "notchy-limit", "status": "ok"}


@api.get("/health", response_model=HealthResponse)
async def health():
    return HealthResponse(ok=True, time=datetime.now(timezone.utc))


@api.get("/stats", response_model=StatsResponse)
async def stats():
    downloads = await _read_counter("downloads")
    waitlist_count = await db.waitlist.count_documents({})
    # Per-provider waitlist breakdown
    providers = {}
    async for row in db.waitlist.aggregate(
        [{"$group": {"_id": "$provider", "count": {"$sum": 1}}}]
    ):
        providers[row["_id"]] = row["count"]
    return StatsResponse(
        downloads=downloads,
        waitlist_count=waitlist_count,
        providers=providers,
        repo_url=GITHUB_REPO_URL,
        releases_url=GITHUB_RELEASES_URL,
    )


@api.post("/waitlist", response_model=WaitlistResponse)
async def join_waitlist(entry: WaitlistEntry):
    email = entry.email.lower().strip()
    provider = entry.provider.lower().strip()
    if provider not in {"gemini", "chatgpt", "cursor", "other"}:
        provider = "gemini"
    doc = {
        "email": email,
        "provider": provider,
        "created_at": datetime.now(timezone.utc).isoformat(),
    }
    deduped = False
    try:
        await db.waitlist.insert_one(doc)
    except Exception as exc:
        # Duplicate key on (email, provider) unique index
        if "E11000" in str(exc) or "duplicate key" in str(exc).lower():
            deduped = True
        else:
            logger.warning(f"waitlist insert failed: {exc}")
            raise HTTPException(status_code=500, detail="waitlist insert failed")
    count = await db.waitlist.count_documents({})
    return WaitlistResponse(ok=True, deduped=deduped, waitlist_count=count)


@api.post("/feedback")
async def feedback(entry: FeedbackEntry):
    doc = entry.model_dump()
    doc["created_at"] = datetime.now(timezone.utc).isoformat()
    await db.feedback.insert_one(doc)
    return {"ok": True}


@api.get("/download/source")
async def download_source():
    try:
        data = await asyncio.get_event_loop().run_in_executor(None, _zip_swift_project)
    except FileNotFoundError as exc:
        raise HTTPException(status_code=500, detail=str(exc))
    except Exception as exc:
        logger.exception("zip failed")
        raise HTTPException(status_code=500, detail=f"zip failed: {exc}")

    await _bump_counter("downloads")
    filename = "notchy-limit-source.zip"
    return StreamingResponse(
        io.BytesIO(data),
        media_type="application/zip",
        headers={
            "Content-Disposition": f'attachment; filename="{filename}"',
            "Content-Length": str(len(data)),
        },
    )


@api.get("/download/dmg")
async def download_dmg():
    """DMG is built by maintainers on macOS. Redirect to GitHub Releases."""
    await _bump_counter("dmg_clicks")
    return RedirectResponse(url=GITHUB_RELEASES_URL, status_code=302)


@api.get("/repo")
async def repo_info():
    return {
        "repo_url": GITHUB_REPO_URL,
        "releases_url": GITHUB_RELEASES_URL,
    }


# ---------------------------------------------------------------------------
# Wire-up
# ---------------------------------------------------------------------------
app.include_router(api)

app.add_middleware(
    CORSMiddleware,
    allow_credentials=True,
    allow_origins=os.environ.get("CORS_ORIGINS", "*").split(","),
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.on_event("startup")
async def on_startup():
    await ensure_indexes()
    logger.info("notchy-limit api ready. Swift project at %s", SWIFT_PROJECT_DIR)


@app.on_event("shutdown")
async def on_shutdown():
    client.close()
