import asyncio
import contextlib
import os
from datetime import datetime, timedelta, timezone
from urllib.parse import urlparse

try:
    from zoneinfo import ZoneInfo
except Exception:
    ZoneInfo = None


RAWAUDIO_CONFIG_VERSION = "2026-07-13-wake-word-barge-in"

DEFAULT_RULE_PROMPT = (
    "将回复处理成纯文字口播版，不要返回 markdown，不要包含代码块，"
    "不要复述这些规则，300字以内。"
)

DEFAULT_SYSTEM_PROMPT_TEMPLATE = (
    "你是运行在音箱上的AI语音助手，不要自称小爱，当前调用 {provider} {model} 模型。"
    "如果用户问你用的是什么模型，只按这个信息回答，不要猜测其他厂商。"
    "回答今天、明天、昨天、星期几等日期时间问题时，必须以系统注入的当前日期时间为准。"
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
    "ds": "deepseek",
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

SWITCH_PROVIDER_ALIASES = {
    "openai模式": "openai",
    "iopenai": "openai",
    "iopenai模式": "openai",
    "openai助手": "openai",
    "openai模型": "openai",
    "欧盆ai": "openai",
    "欧喷ai": "openai",
    "欧朋ai": "openai",
    "欧派ai": "openai",
    "欧盆爱": "openai",
    "欧喷爱": "openai",
    "欧朋爱": "openai",
    "open": "openclaw",
    "opencall": "openclaw",
    "opencloud": "openclaw",
    "爪子": "openclaw",
    "本地模型": "openclaw",
    "本地ai": "openclaw",
    "谷歌": "gemini",
    "gmini": "gemini",
    "欧拉拉": "ollama",
    "欧拉马": "ollama",
    "欧拉玛": "ollama",
    "奥拉马": "ollama",
    "奥拉玛": "ollama",
    "电脑": "ollama",
    "本地电脑": "ollama",
    "局域网模型": "ollama",
    **PROVIDER_ALIASES,
}

SWITCH_COMMAND_ALIASES = {
    "openai": "openai",
    "iopenai": "openai",
    "打开openai": "openai",
    "开启openai": "openai",
    "使用openai": "openai",
    "用openai": "openai",
    "换openai": "openai",
    "换成openai": "openai",
    "openai模式": "openai",
    "切openai": "openai",
    "切到openai": "openai",
    "切iopenai": "openai",
    "切到iopenai": "openai",
    "欧盆ai": "openai",
    "欧喷ai": "openai",
    "欧朋ai": "openai",
    "欧派ai": "openai",
    "打开欧盆ai": "openai",
    "打开欧喷ai": "openai",
    "打开欧朋ai": "openai",
    "切换欧盆ai": "openai",
    "切换欧喷ai": "openai",
    "切换欧朋ai": "openai",
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


def env_bool(name, default):
    raw = os.getenv(name)
    if raw is None or raw == "":
        return default
    return raw.strip().lower() not in ("0", "false", "no", "off", "关闭", "否")


def env_list(name, defaults):
    raw = env(name, "")
    items = []
    for item in raw.replace("，", ",").split(","):
        item = item.strip()
        if item:
            items.append(item)
    return items or defaults


def env_file_path():
    return env("RAWAUDIO_ENV_FILE", "/app/.env")


def env_quote(value):
    if value == "" or any(ch.isspace() or ch in "\"'#$`\\\\" for ch in value):
        escaped = value.replace("\\", "\\\\").replace('"', '\\"')
        return f'"{escaped}"'
    return value


def persist_env_value(name, value):
    path = env_file_path()
    if not path:
        return False
    try:
        lines = []
        found = False
        if os.path.exists(path):
            with open(path, "r", encoding="utf-8") as handle:
                lines = handle.readlines()
        for idx, line in enumerate(lines):
            stripped = line.strip()
            if not stripped or stripped.startswith("#"):
                continue
            candidate = stripped
            if candidate.startswith("export "):
                candidate = candidate[7:].lstrip()
            key = candidate.split("=", 1)[0].strip()
            if key == name:
                prefix = "export " if stripped.startswith("export ") else ""
                newline = "\n" if line.endswith("\n") else ""
                lines[idx] = f"{prefix}{name}={env_quote(value)}{newline}"
                found = True
                break
        if not found:
            if lines and not lines[-1].endswith("\n"):
                lines[-1] += "\n"
            lines.append(f"{name}={env_quote(value)}\n")
        with open(path, "w", encoding="utf-8") as handle:
            handle.writelines(lines)
        return True
    except Exception:
        return False


def compact(text):
    return " ".join(str(text or "").split())


def normalize_text(text):
    return compact(text).replace(" ", "").lower()


def normalize_command_text(text):
    normalized = normalize_text(text)
    for ch in "。.!！?？,，:：；;、'\"“”‘’`":
        normalized = normalized.replace(ch, "")
    return normalized


def selected_provider():
    raw = env("RAWAUDIO_DEFAULT_PROVIDER", env("XIAOAI_DEFAULT_PROVIDER", "deepseek")).strip().lower()
    return PROVIDER_ALIASES.get(raw, raw)


def provider_settings(provider):
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


def openai_compatible_settings():
    provider = selected_provider()
    return provider_settings(provider)


def default_system_prompt(provider, model):
    display_name = PROVIDER_DISPLAY_NAMES.get(provider, provider or "LLM")
    return DEFAULT_SYSTEM_PROMPT_TEMPLATE.format(provider=display_name, model=model or "unknown")


def rawaudio_rule_prompt():
    return compact(env("RAWAUDIO_RULE_PROMPT", DEFAULT_RULE_PROMPT))


def rawaudio_system_prompt(provider, model):
    base_prompt = compact(env("XIAOAI_SYSTEM_PROMPT", default_system_prompt(provider, model)))
    rule_prompt = rawaudio_rule_prompt()
    if not rule_prompt:
        return base_prompt
    return compact(f"{base_prompt} {rule_prompt}")


def current_model_text():
    settings = openai_compatible_settings()
    provider = selected_provider()
    display_name = PROVIDER_DISPLAY_NAMES.get(provider, provider or "LLM")
    model = settings.get("model") or "unknown"
    return f"当前使用 {display_name} {model}。"


def provider_ready(provider):
    settings = provider_settings(provider)
    if not settings.get("base_url"):
        return False
    if provider in ("ollama", "openclaw"):
        return True
    return bool(settings.get("api_key"))


def provider_log_name():
    provider = selected_provider()
    return PROVIDER_DISPLAY_NAMES.get(provider, provider or "LLM")


def base_url_host(base_url):
    parsed = urlparse(base_url or "")
    return parsed.netloc or parsed.path or "unknown"


def route_log_text():
    settings = openai_compatible_settings()
    model = settings.get("model") or "unknown"
    host = base_url_host(settings.get("base_url"))
    return f"→ {model} @ {host}"


def log_provider_route():
    if not env_bool("RAWAUDIO_LOG_ROUTE", True):
        return
    try:
        from core.utils.logger import logger
    except Exception:
        return
    logger.info(route_log_text(), module=provider_log_name())


def local_timezone():
    tz_name = env("RAWAUDIO_TIMEZONE", env("TZ", "Asia/Shanghai"))
    if ZoneInfo:
        try:
            return ZoneInfo(tz_name)
        except Exception:
            pass
    if tz_name in ("Asia/Shanghai", "Asia/Chongqing", "Asia/Harbin", "Asia/Urumqi", "CST-8"):
        return timezone(timedelta(hours=8), "Asia/Shanghai")
    return datetime.now().astimezone().tzinfo


def current_datetime_text():
    now = datetime.now(local_timezone())
    weekdays = ["星期一", "星期二", "星期三", "星期四", "星期五", "星期六", "星期日"]
    weekday = weekdays[now.weekday()]
    return (
        f"当前日期时间：{now.year}年{now.month}月{now.day}日 "
        f"{now.hour:02d}:{now.minute:02d}，{weekday}。"
        "回答今天、明天、昨天、星期几等问题时必须以这个时间为准。"
    )


def is_single_turn_mode():
    return env_bool("RAWAUDIO_SINGLE_TURN", True)


def after_turn_prompt():
    default_prompt = "" if is_single_turn_mode() else env("RAWAUDIO_EXIT_PROMPT", "再见")
    return env("RAWAUDIO_AFTER_TURN_PROMPT", default_prompt)


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


def switch_provider_from_text(text):
    normalized = normalize_command_text(text)
    if normalized in SWITCH_COMMAND_ALIASES:
        return SWITCH_COMMAND_ALIASES[normalized]
    if normalized.startswith("切换到"):
        target = normalized[3:]
    elif normalized.startswith("切换"):
        target = normalized[2:]
    elif normalized.startswith("换到"):
        target = normalized[2:]
    elif normalized.startswith("换成"):
        target = normalized[2:]
    elif normalized.startswith("打开"):
        target = normalized[2:]
    elif normalized.startswith("开启"):
        target = normalized[2:]
    elif normalized.startswith("使用"):
        target = normalized[2:]
    elif normalized.startswith("用"):
        target = normalized[1:]
    else:
        return None
    target = target.strip("。.!！?？,，:：；; ")
    if target.endswith("模式"):
        target = target[:-2]
    target = target.strip("。.!！?？,，:：；; ")
    return SWITCH_PROVIDER_ALIASES.get(target)


def is_wake_word_barge_in_enabled():
    return env_bool("RAWAUDIO_WAKE_WORD_BARGE_IN", True)


def barge_in_grace_seconds():
    return env_int("RAWAUDIO_WAKE_WORD_BARGE_IN_GRACE_MS", 300) / 1000


async def stop_active_playback(controller):
    try:
        import open_xiaoai_server

        token = getattr(controller, "_playback_token", None)
        open_xiaoai_server.stop_tts_playback(token)
    except Exception:
        pass
    try:
        from core.ref import get_speaker

        speaker = get_speaker()
        if speaker:
            await speaker.stop_device_audio()
    except Exception:
        pass


async def wait_for_wake_word_or_tts_done(controller, response):
    try:
        from core.ref import get_kws
    except Exception:
        get_kws = None

    await controller._stop_recording()
    tts_task = asyncio.create_task(controller._play_tts(str(response)))
    kws = get_kws() if get_kws else None
    if not kws:
        await tts_task
        return False

    loop = asyncio.get_running_loop()
    interrupt_future = loop.create_future()
    original_on_message = kws.on_message
    recording_started = False

    def on_wake_word(text):
        def resolve_interrupt():
            if not interrupt_future.done():
                interrupt_future.set_result(text)

        loop.call_soon_threadsafe(resolve_interrupt)

    try:
        try:
            await asyncio.wait_for(asyncio.shield(tts_task), timeout=barge_in_grace_seconds())
            return False
        except asyncio.TimeoutError:
            pass

        kws.on_message = on_wake_word
        await controller._start_recording()
        recording_started = True
        kws.resume()
        done, _ = await asyncio.wait(
            {tts_task, interrupt_future},
            return_when=asyncio.FIRST_COMPLETED,
        )
        if interrupt_future not in done:
            with contextlib.suppress(Exception):
                await tts_task
            return False

        await stop_active_playback(controller)
        if not tts_task.done():
            tts_task.cancel()
            with contextlib.suppress(asyncio.CancelledError):
                await tts_task
        return True
    finally:
        kws.pause()
        kws.on_message = original_on_message
        if not interrupt_future.done():
            interrupt_future.cancel()
        if not tts_task.done():
            tts_task.cancel()
            with contextlib.suppress(asyncio.CancelledError):
                await tts_task
        if recording_started:
            await controller._stop_recording()


async def run_local_turn_with_wake_word_barge_in(controller):
    try:
        from core.ref import get_speaker, get_vad
        from core.services.audio.asr import ASRService
        from core.utils.logger import logger
    except Exception:
        return "error"

    vad = get_vad()
    if not vad:
        logger.error("VAD not available", module=controller.LOG_MODULE)
        return "error"

    text = None
    while getattr(controller, "active", False):
        if text is None:
            speech_bytes = await controller._wait_for_speech(vad)
            if speech_bytes is None:
                return "timeout"
            text = ASRService.asr(speech_bytes, sample_rate=16000)
            if not text:
                logger.debug("ASR empty, retrying", module=controller.LOG_MODULE)
                return "continue"

        for kw in controller.exit_keywords:
            if kw in text:
                logger.info(f"Exit keyword: {kw}", module=controller.LOG_MODULE)
                return "exit"

        full_text = text
        if controller.backend._rule_prompt:
            full_text = text + "\n" + controller.backend._rule_prompt

        run_id = await controller.backend._send_and_track(full_text)
        await controller._play_send_sound()
        response = await controller.backend._wait_response(run_id) if run_id else None
        if response is None:
            logger.warning(f"No response from {controller.BACKEND_NAME}", module=controller.LOG_MODULE)
            speaker = get_speaker()
            if speaker:
                await speaker.play(text="抱歉，我没有收到回复")
            return "continue"

        interrupted = await wait_for_wake_word_or_tts_done(controller, response)
        if interrupted:
            logger.info("⏹️ 唤醒词已打断当前播报，请继续说新问题。", module=provider_log_name())
            await controller._play_notify()
            await controller._start_recording()
            text = None
            continue
        if not is_single_turn_mode():
            await controller._play_notify()
            await controller._start_recording()
            await controller._wait_for_silence(vad)
        return "continue"

    return "exit"


def reload_openai_manager(provider):
    try:
        from core.openai import OpenAIManager
    except Exception:
        return
    settings = provider_settings(provider)
    OpenAIManager._base_url = str(settings.get("base_url") or "").rstrip("/")
    OpenAIManager._api_key = str(settings.get("api_key") or "")
    OpenAIManager._model = str(settings.get("model") or "")
    OpenAIManager._system_prompt = rawaudio_system_prompt(provider, OpenAIManager._model)
    OpenAIManager.reset_session()


def switch_provider(provider):
    if provider not in PROVIDER_DISPLAY_NAMES:
        return "没听清要切换哪个模型。"
    os.environ["RAWAUDIO_DEFAULT_PROVIDER"] = provider
    persist_env_value("RAWAUDIO_DEFAULT_PROVIDER", provider)
    reload_openai_manager(provider)
    try:
        from core.openai_conversation import OpenAIConversationController
        OpenAIConversationController.BACKEND_NAME = provider_log_name()
        OpenAIConversationController.LOG_MODULE = provider_log_name()
    except Exception:
        pass
    display_name = PROVIDER_DISPLAY_NAMES.get(provider, provider)
    if not provider_ready(provider):
        return f"已切换 {display_name}，未配置。"
    return f"已切换 {display_name}。"


def is_ignored_asr_text(text):
    normalized = normalize_text(text)
    if not normalized:
        return True
    if len(normalized) <= 1:
        return True
    ignored_phrases = env_list(
        "RAWAUDIO_IGNORE_ASR_TEXTS",
        ["你好小气", "你好神气", "你好想气", "你好小七", "你好小青", "你好小新"],
    )
    return any(normalized == normalize_text(phrase) for phrase in ignored_phrases)


def install_openai_local_command_patch():
    try:
        from core.openai import OpenAIManager
    except Exception:
        return

    if getattr(OpenAIManager, "_rawaudio_identity_patch_installed", False):
        return

    original_request = OpenAIManager._request_chat_completion
    original_build_messages = OpenAIManager._build_messages

    async def patched_request(cls, text):
        target_provider = switch_provider_from_text(text)
        if target_provider:
            response = switch_provider(target_provider)
            history = cls._sessions.setdefault(cls._session_key, [])
            cls._append_history(history, text, response)
            return response
        if is_model_identity_question(text):
            response = current_model_text()
            history = cls._sessions.setdefault(cls._session_key, [])
            cls._append_history(history, text, response)
            return response
        log_provider_route()
        return await original_request(text)

    def patched_build_messages(cls, history, text):
        messages = original_build_messages(history, text)
        if env_bool("RAWAUDIO_INJECT_DATE", True):
            insert_at = 1 if messages and messages[0].get("role") == "system" else 0
            messages.insert(insert_at, {"role": "system", "content": current_datetime_text()})
        return messages

    OpenAIManager._request_chat_completion = classmethod(patched_request)
    OpenAIManager._build_messages = classmethod(patched_build_messages)
    OpenAIManager._rawaudio_identity_patch_installed = True


def install_provider_log_patch():
    try:
        from core.utils.logger import logger
    except Exception:
        return

    if getattr(logger, "_rawaudio_provider_log_patch_installed", False):
        return

    original_user_speech = logger.user_speech
    original_ai_response = logger.ai_response

    def patched_user_speech(text, module="XiaoZhi"):
        if str(module).startswith("OpenAI"):
            logger.info(f"💬 我说：{text}", module=provider_log_name())
            return
        return original_user_speech(text, module=module)

    def patched_ai_response(text, module="XiaoZhi"):
        if str(module).startswith("OpenAI"):
            logger.info(f"🤖 {text}", module=provider_log_name())
            return
        return original_ai_response(text, module=module)

    logger.user_speech = patched_user_speech
    logger.ai_response = patched_ai_response
    logger._rawaudio_provider_log_patch_installed = True


def install_rawaudio_runtime_patches():
    install_openai_local_command_patch()
    install_provider_log_patch()

    try:
        from core.openai_conversation import OpenAIConversationController
    except Exception:
        return

    OpenAIConversationController.BACKEND_NAME = provider_log_name()
    OpenAIConversationController.LOG_MODULE = provider_log_name()

    if not getattr(OpenAIConversationController, "_rawaudio_single_turn_patch_installed", False):
        original_local_turn = OpenAIConversationController._run_one_turn_with_local_asr
        original_xiaoai_turn = OpenAIConversationController._run_one_turn_with_xiaoai_asr

        async def patched_local_turn(self):
            if is_wake_word_barge_in_enabled():
                result = await run_local_turn_with_wake_word_barge_in(self)
            else:
                result = await original_local_turn(self)
            if is_single_turn_mode() and result == "continue":
                return "timeout"
            return result

        async def patched_xiaoai_turn(self):
            result = await original_xiaoai_turn(self)
            if is_single_turn_mode() and result == "continue":
                return "timeout"
            return result

        OpenAIConversationController._run_one_turn_with_local_asr = patched_local_turn
        OpenAIConversationController._run_one_turn_with_xiaoai_asr = patched_xiaoai_turn
        OpenAIConversationController._rawaudio_single_turn_patch_installed = True

    try:
        from core.services.audio.asr import ASRService
    except Exception:
        return

    if getattr(ASRService, "_rawaudio_ignore_patch_installed", False):
        return

    original_asr = ASRService.asr

    def patched_asr(*args, **kwargs):
        text = original_asr(*args, **kwargs)
        if is_ignored_asr_text(text):
            return ""
        return text

    ASRService.asr = patched_asr
    ASRService._rawaudio_ignore_patch_installed = True


async def before_wakeup(speaker, text, source, app):
    target_provider = switch_provider_from_text(text)
    if target_provider:
        if source == "xiaoai":
            await speaker.abort_xiaoai()
        await speaker.play(text=switch_provider(target_provider))
        return None

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
    prompt = after_turn_prompt()
    if prompt.lower() in ("none", "off", "false", "0", "关闭", "无"):
        return
    if not prompt:
        return
    await speaker.play(text=prompt)


install_rawaudio_runtime_patches()

llm = openai_compatible_settings()
provider = selected_provider()

APP_CONFIG = {
    "wakeup": {
        "keywords": env_list("RAWAUDIO_WAKE_KEYWORDS", ["你好小黑", "小黑小黑"]),
        "timeout": env_int("RAWAUDIO_WAKE_TIMEOUT", 10),
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
        "continuous_conversation_mode": not is_single_turn_mode(),
        "exit_command_keywords": env_list("RAWAUDIO_EXIT_KEYWORDS", ["停止", "退出", "再见"]),
        "max_listening_retries": env_int("RAWAUDIO_MAX_LISTENING_RETRIES", 0 if is_single_turn_mode() else 2),
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
        "system_prompt": rawaudio_system_prompt(provider, llm["model"]),
        "temperature": env_float("LLM_TEMPERATURE", 0.7),
        "max_tokens": env_int("LLM_MAX_TOKENS", 512),
        "history_max_messages": env_int("CONVERSATION_TURNS", 6) * 2,
        "response_timeout": env_int("LLM_TIMEOUT_SECONDS", 120),
        "tts_speed": env_float("RAWAUDIO_TTS_SPEED", 1.0),
        "tts_speaker": env("RAWAUDIO_TTS_SPEAKER", "xiaoai"),
        "session_tts_speakers": {},
        "exit_keywords": env_list("RAWAUDIO_EXIT_KEYWORDS", ["退出", "停止", "再见"]),
        "rule_prompt": "",
        "rule_prompt_for_skill": "",
        "extra_body": {},
    },
}
