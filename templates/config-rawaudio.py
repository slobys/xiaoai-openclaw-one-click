import os


RAWAUDIO_CONFIG_VERSION = "2026-07-12-model-identity"

DEFAULT_SYSTEM_PROMPT_TEMPLATE = (
    "你是运行在小爱音箱上的语音助手，当前使用 {provider} {model} 模型。"
    "如果用户问你用的是什么模型，只按这个信息回答，不要猜测其他厂商。"
    "口播规则：口语化、简短；不要markdown；不要念URL；解释类优先两句话内。"
)

PROVIDER_DISPLAY_NAMES = {
    "deepseek": "DeepSeek",
    "openai": "OpenAI",
    "gemini": "Gemini",
    "ollama": "Ollama",
    "openclaw": "OpenClaw",
    "custom": "Custom OpenAI-compatible",
}


PROVIDER_ALIASES = {
    "deepseek": "deepseek",
    "deep seek": "deepseek",
    "openai": "openai",
    "chatgpt": "openai",
    "gpt": "openai",
    "gemini": "gemini",
    "google": "gemini",
    "谷歌": "gemini",
    "ollama": "ollama",
    "欧拉拉": "ollama",
    "奥拉马": "ollama",
    "openclaw": "openclaw",
    "open": "openclaw",
    "custom": "custom",
}


def env(name, default=""):
    value = os.getenv(name)
    return default if value is None or value == "" else value


def env_int(name, default):
    try:
        value = int(env(name, ""))
        return value if value >= 0 else default
    except ValueError:
        return default


def env_float(name, default):
    try:
        value = float(env(name, ""))
        return value if value >= 0 else default
    except ValueError:
        return default


def env_list(name, defaults):
    raw = env(name, "")
    items = []
    for item in raw.replace("，", ",").split(","):
        item = item.strip()
        if item:
            items.append(item)
    return items or defaults


def compact(text):
    return " ".join(str(text or "").split())


def normalize_text(text):
    return compact(text).replace(" ", "").lower()


def selected_provider():
    raw = env("RAWAUDIO_DEFAULT_PROVIDER", env("XIAOAI_DEFAULT_PROVIDER", "deepseek")).strip().lower()
    return PROVIDER_ALIASES.get(raw, raw)


def openai_compatible_settings():
    provider = selected_provider()
    providers = {
        "deepseek": {
            "base_url": env("DEEPSEEK_BASE_URL", "https://api.deepseek.com"),
            "api_key": env("DEEPSEEK_API_KEY", ""),
            "model": env("DEEPSEEK_MODEL", "deepseek-v4-flash"),
        },
        "openai": {
            "base_url": env("OPENAI_BASE_URL", "https://api.openai.com/v1"),
            "api_key": env("OPENAI_API_KEY", ""),
            "model": env("OPENAI_MODEL", "gpt-4o-mini"),
        },
        "gemini": {
            "base_url": env("GEMINI_BASE_URL", "https://generativelanguage.googleapis.com/v1beta/openai/"),
            "api_key": env("GEMINI_API_KEY", ""),
            "model": env("GEMINI_MODEL", "gemini-3.5-flash"),
        },
        "ollama": {
            "base_url": env("OLLAMA_BASE_URL", "http://192.168.2.193:11434/v1"),
            "api_key": env("OLLAMA_API_KEY", "ollama"),
            "model": env("OLLAMA_MODEL", "qwen3:4b"),
        },
        "openclaw": {
            "base_url": env("OPENCLAW_BASE_URL", "http://192.168.2.238:11435/v1"),
            "api_key": env("OPENCLAW_API_KEY", "xiaoai-local"),
            "model": env("OPENCLAW_DISPLAY_MODEL", env("OPENCLAW_MODEL", "open")),
        },
        "custom": {
            "base_url": env("OPENAI_COMPAT_BASE_URL", env("CUSTOM_BASE_URL", "")),
            "api_key": env("OPENAI_COMPAT_API_KEY", env("CUSTOM_API_KEY", "")),
            "model": env("OPENAI_COMPAT_MODEL", env("CUSTOM_MODEL", "")),
        },
    }
    return providers.get(provider) or providers["deepseek"]


def default_system_prompt(provider, model):
    display_name = PROVIDER_DISPLAY_NAMES.get(provider, provider or "LLM")
    return DEFAULT_SYSTEM_PROMPT_TEMPLATE.format(provider=display_name, model=model or "unknown")


def current_model_text():
    settings = openai_compatible_settings()
    provider = selected_provider()
    display_name = PROVIDER_DISPLAY_NAMES.get(provider, provider or "LLM")
    model = settings.get("model") or "unknown"
    return f"当前使用 {display_name} {model}。"


def is_model_identity_question(text):
    normalized = normalize_text(text)
    if not normalized:
        return False
    phrases = [
        "当前模型",
        "现在模型",
        "所用模型",
        "使用模型",
        "大模型",
        "什么模型",
        "哪个模型",
        "模型是什么",
        "你是什么模型",
        "你用的是什么",
    ]
    return any(phrase in normalized for phrase in phrases)


def install_openai_local_command_patch():
    try:
        from core.openai import OpenAIManager
    except Exception:
        return

    if getattr(OpenAIManager, "_rawaudio_identity_patch_installed", False):
        return

    original_request = OpenAIManager._request_chat_completion

    async def patched_request(cls, text):
        if is_model_identity_question(text):
            response = current_model_text()
            history = cls._sessions.setdefault(cls._session_key, [])
            cls._append_history(history, text, response)
            return response
        return await original_request(text)

    OpenAIManager._request_chat_completion = classmethod(patched_request)
    OpenAIManager._rawaudio_identity_patch_installed = True


async def before_wakeup(speaker, text, source, app):
    if is_model_identity_question(text):
        if source == "xiaoai":
            await speaker.abort_xiaoai()
        await speaker.play(text=current_model_text())
        return None

    if source == "kws":
        prompt = env("RAWAUDIO_WAKE_PROMPT", "我在")
        if prompt.lower() not in ("none", "off", "false", "0", "关闭", "无"):
            await speaker.play(text=prompt)
        return "openai"

    route_keywords = env_list("RAWAUDIO_XIAOAI_ROUTE_KEYWORDS", ["召唤AI", "召唤助手", "召唤小黑"])
    if source == "xiaoai" and any(keyword in text for keyword in route_keywords):
        await speaker.abort_xiaoai()
        return "openai"

    return None


async def after_wakeup(speaker, source=None, session_key=None):
    prompt = env("RAWAUDIO_EXIT_PROMPT", "再见")
    if prompt.lower() in ("none", "off", "false", "0", "关闭", "无"):
        return
    await speaker.play(text=prompt)


install_openai_local_command_patch()

llm = openai_compatible_settings()
provider = selected_provider()

APP_CONFIG = {
    "wakeup": {
        "keywords": env_list("RAWAUDIO_WAKE_KEYWORDS", ["你好小黑", "小黑小黑"]),
        "timeout": env_int("RAWAUDIO_WAKE_TIMEOUT", 20),
        "before_wakeup": before_wakeup,
        "after_wakeup": after_wakeup,
    },
    "kws": {
        "keywords_score": env_float("RAWAUDIO_KWS_SCORE", 2.0),
        "keywords_threshold": env_float("RAWAUDIO_KWS_THRESHOLD", 0.2),
        "min_silence_duration": env_int("RAWAUDIO_KWS_MIN_SILENCE_MS", 480),
    },
    "vad": {
        "threshold": env_float("RAWAUDIO_VAD_THRESHOLD", 0.10),
        "min_speech_duration": env_int("RAWAUDIO_VAD_MIN_SPEECH_MS", 250),
        "min_silence_duration": env_int("RAWAUDIO_VAD_MIN_SILENCE_MS", 500),
    },
    "audio_input": {
        "gain": env_float("RAWAUDIO_INPUT_GAIN", 1.0),
    },
    "asr": {
        "model": env("RAWAUDIO_ASR_MODEL", "sense_voice"),
        "int8": env("RAWAUDIO_ASR_INT8", "true").lower() not in ("0", "false", "no", "off"),
    },
    "xiaoai": {
        "continuous_conversation_mode": True,
        "exit_command_keywords": env_list("RAWAUDIO_EXIT_KEYWORDS", ["停止", "退出", "再见"]),
        "max_listening_retries": env_int("RAWAUDIO_MAX_LISTENING_RETRIES", 2),
        "exit_prompt": env("RAWAUDIO_EXIT_PROMPT", "再见"),
        "continuous_conversation_keywords": env_list(
            "RAWAUDIO_CONTINUOUS_KEYWORDS",
            ["开启连续对话", "启动连续对话", "我想跟你聊天"],
        ),
    },
    "tts": {
        "doubao": {
            "app_id": env("DOUBAO_TTS_APP_ID", ""),
            "access_key": env("DOUBAO_TTS_ACCESS_KEY", ""),
            "default_speaker": env("DOUBAO_TTS_SPEAKER", "zh_female_vv_uranus_bigtts"),
            "audio_format": env("DOUBAO_TTS_FORMAT", "pcm"),
            "stream": env("DOUBAO_TTS_STREAM", "true").lower() not in ("0", "false", "no", "off"),
        },
    },
    "openai": {
        "base_url": llm["base_url"],
        "api_key": llm["api_key"],
        "model": llm["model"],
        "input_mode": "local_asr",
        "session_key": "xiaoai-rawaudio",
        "system_prompt": compact(env("XIAOAI_SYSTEM_PROMPT", default_system_prompt(provider, llm["model"]))),
        "temperature": env_float("LLM_TEMPERATURE", 0.7),
        "max_tokens": env_int("LLM_MAX_TOKENS", 512),
        "history_max_messages": env_int("CONVERSATION_TURNS", 6) * 2,
        "response_timeout": env_int("LLM_TIMEOUT_SECONDS", 120),
        "tts_speed": env_float("RAWAUDIO_TTS_SPEED", 1.0),
        "tts_speaker": env("RAWAUDIO_TTS_SPEAKER", "xiaoai"),
        "session_tts_speakers": {},
        "exit_keywords": env_list("RAWAUDIO_EXIT_KEYWORDS", ["退出", "停止", "再见"]),
        "rule_prompt": env(
            "RAWAUDIO_RULE_PROMPT",
            "注意：将结果处理成纯文字版，不要返回任何 markdown 格式，也不要包含任何代码块，并将字数控制在300字以内",
        ),
        "rule_prompt_for_skill": "",
        "extra_body": {},
    },
}
