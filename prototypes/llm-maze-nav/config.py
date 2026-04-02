"""
Configuration for LLM Maze Navigation Prototype.
All tuning knobs in one place.
"""

# --- Maze ---
MAZE_WIDTH = 7
MAZE_HEIGHT = 7

# --- Fog of War ---
VISION_RADIUS = 3

# --- Keys & Objective ---
KEY_ORDER = ["BRASS", "JADE", "CRYSTAL"]

# --- LLM Agent ---
OLLAMA_BASE_URL = "http://localhost:11434"
OLLAMA_MODEL = "qwen2.5:14b"
OLLAMA_TEMPERATURE = 0.3  # low temperature for more deterministic decisions
OLLAMA_NUM_CTX = 4096  # context window size

# --- Formatter ---
INCLUDE_ASCII_MAP = False  # start with coordinate list only (GDD default)
INCLUDE_EXPLORED = True
MAX_VISITED_COUNT = 20
MAX_EXPLORED_COUNT = 30

# --- Runner ---
MAX_TICKS = 200  # max ticks before declaring failure
NUM_TRIALS = 5  # trials per configuration
RANDOM_SEED = 42  # for reproducible maze generation (None = random)
