package com.osfans.trime;

import android.os.Handler;
import android.os.Looper;
import android.util.Base64;
import android.util.Log;

import com.google.gson.Gson;
import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;

import okhttp3.*;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.util.Map;
import java.util.concurrent.TimeUnit;

public class AiClient {

    private final String baseUrl;
    private final String apiKey;
    private final OkHttpClient httpClient;
    private final Gson gson = new Gson();
    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private String mModel;
    private String mSystemPrompt;
    private String mPrompt;
    private String mExtraParams;
    // true → 走 /audio/transcriptions 的 multipart 上传(专用 ASR 模型)
    // false → 走 /chat/completions 的 input_audio / audio_url(多模态理解模型)
    private boolean mTranscribeMode = false;
    private boolean mTranscribeModeSet = false;

    public void setModel(String model) {
        mModel = model;
        if (!mTranscribeModeSet) mTranscribeMode = looksLikeAsr(model);
    }

    /** 专用语音识别模型名:这类模型只接受 multipart 转写,发多模态消息会被拒或按 token 高价计费 */
    public static boolean looksLikeAsr(String model) {
        if (model == null) return false;
        String m = model.toLowerCase();
        return m.contains("sensevoice") || m.contains("whisper")
                || m.contains("paraformer") || m.contains("transcrib")
                || m.contains("-asr") || m.contains("asr-");
    }

    /** 手动指定是否走转写接口(主题里 asr_config.api 可覆盖自动判断) */
    public void setTranscribeMode(boolean on) {
        mTranscribeMode = on;
        mTranscribeModeSet = true;
    }

    public boolean isTranscribeMode() {
        return mTranscribeMode;
    }

    public void setSystemPrompt(String systemPrompt) {
        mSystemPrompt = systemPrompt;
    }

    public void setPrompt(String prompt) {
        mPrompt = prompt;
    }

    public void setExtraParams(String extraParams) {
        mExtraParams = extraParams;
    }

    /**
     * 统一回调接口
     */
    public interface AiCallback {
        void onSuccess(String result);

        void onFailure(Exception e);
    }

    /**
     * 构造方法：仅需传入 Base URL 和 API Key
     */
    public AiClient(String baseUrl, String apiKey) {
        this.baseUrl = baseUrl.endsWith("/") ? baseUrl.substring(0, baseUrl.length() - 1) : baseUrl;
        this.apiKey = apiKey;
        this.httpClient = new OkHttpClient.Builder()
                .connectTimeout(120, TimeUnit.SECONDS)
                .readTimeout(120, TimeUnit.SECONDS)
                .build();
        mPrompt = "";
    }

    // =========================================================================
    //  单次请求 / 开启新对话方法 (返回 AiSession 实例)
    // =========================================================================

    /**
     * 创建一个新的空白会话
     */

    public AiSession createSession() {
        return createSession(mModel);
    }

    public AiSession createSession(String model) {
        return createSession(model, mSystemPrompt);
    }

    /**
     * 创建带有系统提示词的会话
     */
    public AiSession createSession(String model, String systemPrompt) {
        return new AiSession(this, model, systemPrompt,mExtraParams);
    }

    /**
     * 纯文字聊天（创建新会话并立即异步发送请求，返回 AiSession）
     */
    public AiSession chat(String prompt, AiCallback callback) {
        return chat(mModel, prompt, callback);
    }

    public AiSession chat(String model, String prompt, AiCallback callback) {
        return chat(model, mSystemPrompt, prompt, mExtraParams, callback);
    }

    public AiSession chat(String model, String systemPrompt, String prompt, String extraJsonParams, AiCallback callback) {
        AiSession session = new AiSession(this, model, systemPrompt);
        session.chat(mPrompt+prompt, extraJsonParams, callback);
        return session;
    }

    /**
     * 图片识别 / 图片问答（创建新会话并发送，返回 AiSession）
     */
    public AiSession recognizeImage(byte[] imageBytes, AiCallback callback) {
        return recognizeImage(mModel, mSystemPrompt, mPrompt, imageBytes, "image/jpeg", mExtraParams, callback);
    }

    public AiSession recognizeImage(String prompt, byte[] imageBytes, AiCallback callback) {
        return recognizeImage(mModel, mSystemPrompt, prompt, imageBytes, "image/jpeg", mExtraParams, callback);
    }

    public AiSession recognizeImage(String model, String prompt, byte[] imageBytes, AiCallback callback) {
        return recognizeImage(model, mSystemPrompt, prompt, imageBytes, "image/jpeg", mExtraParams, callback);
    }

    public AiSession recognizeImage(String model, String prompt, byte[] imageBytes, String mimeType, AiCallback callback) {
        return recognizeImage(model, mSystemPrompt, prompt, imageBytes, mimeType, mExtraParams, callback);
    }

    public AiSession recognizeImage(String model, String systemPrompt, String prompt, byte[] imageBytes, String mimeType, String extraJsonParams, AiCallback callback) {
        AiSession session = new AiSession(this, model, systemPrompt);
        session.recognizeImage(prompt, imageBytes, mimeType, extraJsonParams, callback);
        return session;
    }

    /**
     * 语音识别（创建新会话并发送，返回 AiSession）
     */
    public AiSession recognizeAudio(byte[] audioBytes, AiCallback callback) {
        return recognizeAudio(mModel, mSystemPrompt, mPrompt, audioBytes, null, mExtraParams, callback);
    }

    public AiSession recognizeAudio(String model, String prompt, byte[] audioBytes, String audioFormat, AiCallback callback) {
        return recognizeAudio(model, mSystemPrompt, prompt, audioBytes, audioFormat, mExtraParams, callback);
    }

    public AiSession recognizeAudio(String model, String systemPrompt, String prompt, byte[] audioBytes, String audioFormat, String extraJsonParams, AiCallback callback) {
        AiSession session = new AiSession(this, model, systemPrompt);
        session.recognizeAudio(prompt, audioBytes, audioFormat, extraJsonParams, callback);
        return session;
    }

    // =========================================================================
    //  专用 ASR 转写(/audio/transcriptions)
    // =========================================================================

    /**
     * 把整段 WAV 上传到 OpenAI 兼容的 /v1/audio/transcriptions,取回 {"text": "..."}。
     * <p>
     * 和 recognizeAudio 的区别:那边是"让多模态大模型听音频",音频会折算成大量
     * token(百炼 omni 音频输入 15.8 元/百万 token),而且模型还要再生成一遍文本;
     * 这边是专用识别模型按音频时长/字符计价,硅基流动 SenseVoiceSmall 长期免费,
     * 单次可传 ≤50MB / ≤1 小时,完全绕开系统引擎 10 秒截断。
     */
    public void transcribeAudio(byte[] wav, AiCallback callback) {
        transcribeAudio(mModel, wav, callback);
    }

    public void transcribeAudio(String model, byte[] wav, final AiCallback callback) {
        if (wav == null || wav.length == 0) {
            postFailure(callback, new IllegalArgumentException("录音为空,没有可识别的内容"));
            return;
        }
        if (baseUrl == null || baseUrl.trim().isEmpty()) {
            postFailure(callback, new IllegalArgumentException("Base URL 未配置"));
            return;
        }
        if (model == null || model.trim().isEmpty()) {
            postFailure(callback, new IllegalArgumentException("模型名未配置"));
            return;
        }

        // baseUrl 允许写成 .../v1、.../v1/chat/completions 或只有域名,统一收敛到 .../v1
        String root = baseUrl.trim();
        int cut = root.indexOf("/chat/completions");
        if (cut > 0) root = root.substring(0, cut);
        while (root.endsWith("/")) root = root.substring(0, root.length() - 1);
        if (!root.endsWith("/v1") && !root.contains("/v1/")) root = root + "/v1";
        String url = root + "/audio/transcriptions";

        RequestBody fileBody = RequestBody.create(wav, MediaType.get("audio/wav"));
        MultipartBody body = new MultipartBody.Builder()
                .setType(MultipartBody.FORM)
                .addFormDataPart("file", "audio.wav", fileBody)
                .addFormDataPart("model", model)
                .build();

        Log.w("speech", "transcribeAudio: " + url + " model=" + model + " audio=" + wav.length + "B");

        Request request = new Request.Builder()
                .url(url)
                .header("Authorization", "Bearer " + apiKey)
                .post(body)
                .build();

        httpClient.newCall(request).enqueue(new Callback() {
            @Override
            public void onFailure(Call call, IOException e) {
                postFailure(callback, e);
            }

            @Override
            public void onResponse(Call call, Response response) {
                try (Response res = response) {
                    String respBody = res.body() != null ? res.body().string() : "";
                    if (!res.isSuccessful()) {
                        String brief = respBody.length() > 300 ? respBody.substring(0, 300) : respBody;
                        postFailure(callback, new Exception("转写失败 [" + res.code() + "]: " + brief));
                        return;
                    }
                    String text = parseTranscript(respBody);
                    if (text == null || text.trim().isEmpty()) {
                        postFailure(callback, new Exception("没有识别到文字"));
                        return;
                    }
                    final String out = text.trim();
                    mainHandler.post(() -> {
                        if (callback != null) callback.onSuccess(out);
                    });
                } catch (Exception e) {
                    postFailure(callback, e);
                }
            }
        });
    }

    /** 兼容 {"text":"..."} 与纯文本两种返回 */
    private String parseTranscript(String body) {
        if (body == null) return null;
        String t = body.trim();
        if (t.startsWith("{")) {
            try {
                JsonObject o = JsonParser.parseString(t).getAsJsonObject();
                if (o.has("text") && !o.get("text").isJsonNull()) return o.get("text").getAsString();
                // 少数平台把结果放在 output_text / transcription
                if (o.has("output_text")) return o.get("output_text").getAsString();
                if (o.has("transcription")) return o.get("transcription").getAsString();
            } catch (Exception e) {
                Log.w("speech", "parseTranscript failed", e);
            }
        }
        return t;
    }

    // =========================================================================
    //  网络请求底层异步封装
    // =========================================================================

    protected void executeAsyncRequest(String model, JsonArray messages, String extraJsonParams, final AiCallback callback) {
        JsonObject json = new JsonObject();

        if (extraJsonParams != null && !extraJsonParams.trim().isEmpty()) {
            try {
                JsonObject extraObj = JsonParser.parseString(extraJsonParams).getAsJsonObject();
                mergeJsonObject(json, extraObj);
            } catch (Exception e) {
                postFailure(callback, new Exception("Invalid extraJsonParams JSON: " + e.getMessage(), e));
                return;
            }
        }

        json.addProperty("model", model);
        json.add("messages", messages);

        RequestBody body = RequestBody.create(
                json.toString(),
                MediaType.get("application/json; charset=utf-8")
        );

        String fullPath = baseUrl.contains("/chat/completions") ? baseUrl : baseUrl + "/chat/completions";
        // 1. 判空检查
        if (baseUrl == null || baseUrl.trim().isEmpty()) {
            postFailure(callback, new IllegalArgumentException("Base URL cannot be null or empty."));
            return;
        }

        String trimmedBaseUrl = baseUrl.trim();

// 2. 校验 Base URL 格式并获取具体英文错误原因
        String errorReason = getUrlErrorReason(trimmedBaseUrl);
        if (errorReason != null) {
            postFailure(callback, new IllegalArgumentException(errorReason));
            return;
        }

// 3. 解析 Base URL（此时已确保一定会解析成功，不会为 null）
        HttpUrl baseUrlObj = HttpUrl.parse(trimmedBaseUrl);

        HttpUrl.Builder urlBuilder = baseUrlObj.newBuilder();

// 如果 baseUrl 本身还没包含 completions 路径，则安全地追加
        if (!baseUrlObj.encodedPath().endsWith("/chat/completions")) {
            urlBuilder.addPathSegment("chat")
                    .addPathSegment("completions");
        }

        // HttpUrl finalUrl = urlBuilder.build();
        // HttpUrl.Builder urlBuilder = HttpUrl.parse(fullPath).newBuilder();
        if (fullPath.contains("googleapis.com")) {
            urlBuilder.addQueryParameter("key", apiKey);
        }

        Request request = new Request.Builder()
                .url(urlBuilder.build())
                .header("Authorization", "Bearer " + apiKey)
                .post(body)
                .build();

        httpClient.newCall(request).enqueue(new Callback() {
            @Override
            public void onFailure(Call call, IOException e) {
                postFailure(callback, e);
            }

            @Override
            public void onResponse(Call call, Response response) throws IOException {
                /*BufferedReader stream = new BufferedReader(new InputStreamReader(response.body().byteStream()));
                String line = stream.readLine();
                while (line!=null) {
                    Log.w("speech", "onResponse: "+line );
                    line = stream.readLine();
                }*/


                try (Response res = response) {

                    String respBody = res.body() != null ? res.body().string() : "";
                    if (!res.isSuccessful()) {
                        postFailure(callback, new Exception("API Request Failed [" + res.code() + "]: " + respBody));
                        return;
                    }

                    JsonObject respJson = gson.fromJson(respBody, JsonObject.class);
                    String content = respJson.getAsJsonArray("choices")
                            .get(0).getAsJsonObject()
                            .getAsJsonObject("message")
                            .get("content").getAsString();

                    postSuccess(callback, content);
                } catch (Exception e) {
                    postFailure(callback, new Exception("Failed to parse API response: " + e.getMessage(), e));
                }
            }
        });
    }
    /**
     * 校验 URL 格式并返回详细的英文错误原因。若 URL 合法，返回 null。
     */
    private String getUrlErrorReason(String urlString) {
        try {
            java.net.URI uri = new java.net.URI(urlString);

            // 检查协议 (Scheme)
            String scheme = uri.getScheme();
            if (scheme == null) {
                return "Invalid Base URL: Missing protocol scheme (must start with 'http://' or 'https://').";
            }
            if (!scheme.equalsIgnoreCase("http") && !scheme.equalsIgnoreCase("https")) {
                return "Invalid Base URL: Unsupported protocol scheme '" + scheme + "' (only 'http' and 'https' are allowed).";
            }

            // 检查主机名 (Host)
            if (uri.getHost() == null) {
                return "Invalid Base URL: Missing host name (e.g., 'https://api.openai.com').";
            }

        } catch (java.net.URISyntaxException e) {
            // 返回 Java URI 解析捕获到的具体英文错误原因及位置
            if (e.getIndex() != -1) {
                return String.format("Invalid Base URL syntax at index %d: %s", e.getIndex(), e.getReason());
            } else {
                return "Invalid Base URL syntax: " + e.getReason();
            }
        }

        // 双重校验：确保 OkHttp 能正常解析
        if (okhttp3.HttpUrl.parse(urlString) == null) {
            return "Invalid Base URL: Unable to parse into a valid HTTP/HTTPS URL.";
        }

        return null; // 代表网址合法
    }
    private void postSuccess(final AiCallback callback, final String result) {
        if (callback == null) return;
        mainHandler.post(() -> callback.onSuccess(result));
    }

    private void postFailure(final AiCallback callback, final Exception e) {
        if (callback == null) return;
        mainHandler.post(() -> callback.onFailure(e));
    }

    private void mergeJsonObject(JsonObject target, JsonObject source) {
        for (Map.Entry<String, JsonElement> entry : source.entrySet()) {
            String key = entry.getKey();
            JsonElement value = entry.getValue();

            if (value.isJsonObject() && target.has(key) && target.get(key).isJsonObject()) {
                mergeJsonObject(target.getAsJsonObject(key), value.getAsJsonObject());
            } else {
                target.add(key, value);
            }
        }
    }

    // =========================================================================
    //  会话对象内部类 (保持多轮上下文状态)
    // =========================================================================

    public static class AiSession {
        private final AiClient client;
        private final String model;
        private final JsonArray history = new JsonArray();
        private String lastResponseText = "";
        private String mExtraJsonParams;

        public AiSession(AiClient client, String model) {
            this(client, model, null);
        }

        public AiSession(AiClient client, String model, String systemPrompt) {
            this.client = client;
            this.model = model;
            setSystemPrompt(systemPrompt);
        }

        public AiSession(AiClient client, String model, String systemPrompt, String extraParams) {
            this.client = client;
            this.model = model;
            setSystemPrompt(systemPrompt);
            mExtraJsonParams = extraParams;
        }

        /**
         * 设置或更新系统提示词 (如果已存在系统提示词则覆盖，不存在则插到头部)
         */
        /**
         * 设置或更新系统提示词 (如果已存在系统提示词则覆盖，不存在则插到头部)
         */
        public void setSystemPrompt(String systemPrompt) {
            if (systemPrompt == null || systemPrompt.trim().isEmpty()) {
                return;
            }

            JsonObject systemMsg = new JsonObject();
            systemMsg.addProperty("role", "system");
            systemMsg.addProperty("content", systemPrompt);

            // 1. 如果 history 第一条已经是 system，直接覆盖更新
            if (history.size() > 0) {
                JsonObject firstMsg = history.get(0).getAsJsonObject();
                if (firstMsg.has("role") && "system".equals(firstMsg.get("role").getAsString())) {
                    history.set(0, systemMsg);
                    return;
                }
            } else {
                history.add(systemMsg);
                return;
            }

            // 2. 备份原有的历史元素
            JsonArray temp = history.deepCopy();

            // 3. 循环删除 index 0，直至 history 完全清空（兼容所有 Gson 版本）
            while (history.size() > 0) {
                history.remove(0);
            }

            // 4. 将 system 插入最前面，再把原有的历史记录追加回来
            history.add(systemMsg);
            history.addAll(temp);
        }

        /**
         * 连续对话：发送纯文本消息
         */
        public void chat(String prompt, AiCallback callback) {
            chat(prompt, mExtraJsonParams, callback);
        }

        public void chat(String prompt, String extraJsonParams, AiCallback callback) {
            mExtraJsonParams=extraJsonParams;
            JsonObject userMsg = new JsonObject();
            userMsg.addProperty("role", "user");
            userMsg.addProperty("content", prompt);
            history.add(userMsg);

            executeAndAppendResponse(extraJsonParams, callback);
        }

        /**
         * 连续对话：补充图片问答
         */
        public void recognizeImage(String prompt, byte[] imageBytes, String mimeType, AiCallback callback) {
            recognizeImage(prompt, imageBytes, mimeType, mExtraJsonParams, callback);
        }

        public void recognizeImage(String prompt, byte[] imageBytes, String mimeType, String extraJsonParams, AiCallback callback) {
            mExtraJsonParams=extraJsonParams;
            String base64Image = Base64.encodeToString(imageBytes, Base64.NO_WRAP);
            String dataUrl = "data:" + (mimeType != null ? mimeType : "image/jpeg") + ";base64," + base64Image;

            JsonArray contentArray = new JsonArray();
            JsonObject textObj = new JsonObject();
            textObj.addProperty("type", "text");
            textObj.addProperty("text", prompt != null && !prompt.isEmpty() ? prompt : "请识别并描述这张图片");
            contentArray.add(textObj);

            JsonObject imageObj = new JsonObject();
            imageObj.addProperty("type", "image_url");
            JsonObject imageUrlObj = new JsonObject();
            imageUrlObj.addProperty("url", dataUrl);
            imageObj.add("image_url", imageUrlObj);
            contentArray.add(imageObj);

            JsonObject userMsg = new JsonObject();
            userMsg.addProperty("role", "user");
            userMsg.add("content", contentArray);
            history.add(userMsg);

            executeAndAppendResponse(extraJsonParams, callback);
        }

        /**
         * 连续对话：补充语音识别
         */
        public void recognizeAudio(byte[] audioBytes, AiCallback callback) {
            recognizeAudio(null, audioBytes, null, mExtraJsonParams, callback);
        }

        public void recognizeAudio(String prompt, byte[] audioBytes, String audioFormat, AiCallback callback) {
            recognizeAudio(prompt, audioBytes, audioFormat, mExtraJsonParams, callback);
        }

        public void recognizeAudio(String prompt, byte[] audioBytes, String audioFormat, String extraJsonParams, AiCallback callback) {
            mExtraJsonParams=extraJsonParams;
            String base64Audio = Base64.encodeToString(audioBytes, Base64.NO_WRAP);
            String dataUrl = "data:audio/" + (audioFormat != null ? audioFormat : "wav") + ";base64," + base64Audio;

            JsonArray contentArray = new JsonArray();
            JsonObject textObj = new JsonObject();
            textObj.addProperty("type", "text");
            textObj.addProperty("text", prompt != null && !prompt.isEmpty() ? prompt : "请将音频中的语音内容完整转写为文本，不要添加解释");
            contentArray.add(textObj);

            // 硅基流动的多模态接口用 audio_url(值仍是同一个 data URI),
            // 其他平台(OpenAI / 百炼 / 智谱)保持标准的 input_audio。
            JsonObject audioObj = new JsonObject();
            if (client.baseUrl != null && client.baseUrl.toLowerCase().contains("siliconflow")) {
                audioObj.addProperty("type", "audio_url");
                JsonObject audioUrl = new JsonObject();
                audioUrl.addProperty("url", dataUrl);
                audioObj.add("audio_url", audioUrl);
            } else {
                audioObj.addProperty("type", "input_audio");
                JsonObject inputAudio = new JsonObject();
                inputAudio.addProperty("data", dataUrl);
                inputAudio.addProperty("format", audioFormat != null ? audioFormat : "wav");
                audioObj.add("input_audio", inputAudio);
            }
            contentArray.add(audioObj);

            JsonObject userMsg = new JsonObject();
            userMsg.addProperty("role", "user");
            userMsg.add("content", contentArray);
            history.add(userMsg);
            // 只打印摘要:整个请求体含 base64 音频(数 MB),打进 logcat 会拖慢并刷屏
            Log.w("speech", "recognizeAudio: audio=" + audioBytes.length + "B format="
                    + (audioFormat != null ? audioFormat : "wav") + " base64=" + base64Audio.length()
                    + " chars prompt=" + prompt);
            executeAndAppendResponse(extraJsonParams, callback);
        }

        private void executeAndAppendResponse(String extraJsonParams, final AiCallback callback) {
            try {
                client.executeAsyncRequest(model, history, extraJsonParams, new AiCallback() {
                    @Override
                    public void onSuccess(String result) {
                        lastResponseText = result;

                        // 收到结果后，同步更新历史上下文
                        JsonObject assistantMsg = new JsonObject();
                        assistantMsg.addProperty("role", "assistant");
                        assistantMsg.addProperty("content", result);
                        history.add(assistantMsg);

                        if (callback != null) {
                            callback.onSuccess(result);
                        }
                    }

                    @Override
                    public void onFailure(Exception e) {
                        if (callback != null) {
                            callback.onFailure(e);
                        }
                    }
                });
            }catch (Exception e){
                if (callback != null) {
                    callback.onFailure(e);
                }
            }
        }

        public String getLastResponseText() {
            return lastResponseText;
        }

        public JsonArray getHistory() {
            return history;
        }
    }
}
