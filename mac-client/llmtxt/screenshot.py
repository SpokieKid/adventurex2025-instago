import json
import base64
# from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from typing import List, Optional
from uuid import UUID

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile, status, Query
from sqlalchemy.orm import Session

from app.workflows import ai_agent
from app.workflows.openai_agent import OpenAIAgent
from app.workflows.gemini_agent import GeminiAgent
from app.workflows.openrouter_agent import OpenRouterAgent
from app.core.auth import get_current_user_id
from app.core.config import settings
from app.core.logging import get_logger
from app.db.base import get_db
from app.models import Screenshot
from app.models.schemas import ScreenshotResponse, ScreenshotUpdate, ScreenshotCreate
from app.services.storage import storage_service, StorageService
from app.services.vector_store import vector_service
from app.services.embedding import embedding_service

router = APIRouter()
# executor = ThreadPoolExecutor(max_workers=5)
logger = get_logger(__name__)


@router.post("/screenshot", response_model=ScreenshotResponse, status_code=status.HTTP_201_CREATED)
async def upload_screenshot(
    screenshot_data: ScreenshotCreate,
    current_user_id: str = Depends(get_current_user_id),
    db: Session = Depends(get_db)
):
    # Decode base64 image
    try:
        content = base64.b64decode(screenshot_data.screenshotFileBlob)
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid base64 image data"
        )

    # Default to PNG if not specified
    content_type = "image/png"

    image_url, thumbnail_url, metadata = await storage_service.upload_screenshot(
        content, current_user_id, content_type
    )

    # Convert Unix timestamp to datetime
    screenshot_time = datetime.fromtimestamp(screenshot_data.screenshotTimestamp, tz=timezone.utc)

    screenshot = Screenshot(
        user_id=current_user_id,
        image_url=image_url,
        thumbnail_url=thumbnail_url,
        width=metadata["width"],
        height=metadata["height"],
        file_size=metadata["file_size"],
        user_note=f"{screenshot_data.screenshotAppName}: {screenshot_data.screenshotTags}",
        created_at=screenshot_time  # Use the timestamp from client
    )

    db.add(screenshot)
    db.commit()
    db.refresh(screenshot)

    # Select AI agent based on AGENT_NAME configuration
    if settings.AGENT_NAME == "gemini":
        selected_agent = GeminiAgent()
    elif settings.AGENT_NAME == "openrouter":
        selected_agent = OpenRouterAgent()
    else:
        selected_agent = OpenAIAgent()  # Default to OpenAI

    # Comment out executor.submit and use await instead
    # executor.submit(
    #     process_screenshot_async,
    #     str(screenshot.id),
    #     image_url,
    #     screenshot_data.screenshotFileBlob,  # Pass base64 directly
    #     selected_agent
    # )
    
    # Process screenshot synchronously in the same pipeline
    await process_screenshot_async(
        str(screenshot.id),
        image_url,
        screenshot_data.screenshotFileBlob,  # Pass base64 directly
        selected_agent,
        db
    )

    return ScreenshotResponse.from_db(screenshot)


async def process_screenshot_async(screenshot_id: str, image_url: str, base64_content: str, agent=None, db: Session = None):
    try:
        # Use provided db session or create a new one
        close_db = False
        if db is None:
            from app.db.base import SessionLocal
            db = SessionLocal()
            close_db = True

        # Get screenshot to access user_id
        screenshot = db.query(Screenshot).filter(Screenshot.id == screenshot_id).first()
        if not screenshot:
            return

        # Use provided agent or default
        if agent is None:
            agent = ai_agent

        result = agent.process_screenshot(base64_content)

        # Generate embedding using dedicated embedding service
        embedding = embedding_service.generate_embedding_from_screenshot_data(
            title=result["title"],
            description=result["description"],
            tags=result["tags"],
            markdown=result["markdown"]
        )

        vector_id = vector_service.add_screenshot(screenshot_id, embedding, str(screenshot.user_id))

        # Update screenshot with AI results
        screenshot.ai_title = result["title"]
        screenshot.ai_description = result["description"]
        screenshot.ai_tags = json.dumps(result["tags"])
        screenshot.markdown_content = result["markdown"]
        screenshot.vector_id = vector_id

        db.commit()

    except Exception as e:
        print(f"Error processing screenshot {screenshot_id}: {e}")
    finally:
        if close_db:
            db.close()


@router.get("/screenshot-note", response_model=List[ScreenshotResponse])
async def get_screenshots(
    skip: int = 0,
    limit: int = 20,
    current_user_id: str = Depends(get_current_user_id),
    db: Session = Depends(get_db)
):
    logger.info(f"Fetching screenshots for user: {current_user_id}, skip: {skip}, limit: {limit}")
    screenshots = db.query(Screenshot).filter(
        Screenshot.user_id == current_user_id
    ).order_by(Screenshot.created_at.desc()).offset(skip).limit(limit).all()

    # Refresh signed URLs for each screenshot
    storage_service = StorageService()
    responses = []
    for screenshot in screenshots:
        response = ScreenshotResponse.from_db(screenshot)
        # Refresh the signed URL if it exists
        if response.image_url:
            response.image_url = storage_service.refresh_signed_url(response.image_url)
        responses.append(response)
    
    return responses


@router.get("/screenshot-note/{screenshot_id}", response_model=ScreenshotResponse)
async def get_screenshot(
    screenshot_id: UUID,
    current_user_id: str = Depends(get_current_user_id),
    db: Session = Depends(get_db)
):
    screenshot = db.query(Screenshot).filter(
        Screenshot.id == screenshot_id,
        Screenshot.user_id == current_user_id
    ).first()

    if not screenshot:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Screenshot not found"
        )

    response = ScreenshotResponse.from_db(screenshot)
    
    # Refresh the signed URL if it exists
    if response.image_url:
        storage_service = StorageService()
        response.image_url = storage_service.refresh_signed_url(response.image_url)
    
    return response


@router.put("/screenshot-note/{screenshot_id}", response_model=ScreenshotResponse)
async def update_screenshot(
    screenshot_id: UUID,
    update_data: ScreenshotUpdate,
    current_user_id: str = Depends(get_current_user_id),
    db: Session = Depends(get_db)
):
    screenshot = db.query(Screenshot).filter(
        Screenshot.id == screenshot_id,
        Screenshot.user_id == current_user_id
    ).first()

    if not screenshot:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Screenshot not found"
        )

    if update_data.user_note is not None:
        screenshot.user_note = update_data.user_note

    if update_data.ai_tags is not None:
        screenshot.ai_tags = json.dumps(update_data.ai_tags)

    db.commit()
    db.refresh(screenshot)

    return ScreenshotResponse.from_db(screenshot)


@router.delete("/screenshot/{screenshot_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_screenshot(
    screenshot_id: UUID,
    current_user_id: str = Depends(get_current_user_id),
    db: Session = Depends(get_db)
):
    screenshot = db.query(Screenshot).filter(
        Screenshot.id == screenshot_id,
        Screenshot.user_id == current_user_id
    ).first()

    if not screenshot:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Screenshot not found"
        )

    await storage_service.delete_screenshot(screenshot.image_url, screenshot.thumbnail_url)

    if screenshot.vector_id:
        vector_service.delete_screenshot(screenshot.vector_id)

    db.delete(screenshot)
    db.commit()
