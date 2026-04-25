## PillPals Backend (FastAPI)

### Quickstart

```bash
cd backend
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --reload --port 8000
```

### Docs

- Swagger UI: `http://localhost:8000/docs`
- Health: `GET /health`

