"""Start the dev server: uv run python backend/run.py"""
from app import create_app

if __name__ == "__main__":
    create_app().run(debug=True)
