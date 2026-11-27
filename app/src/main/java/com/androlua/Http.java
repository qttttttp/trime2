package com.androlua;

import android.webkit.MimeTypeMap;

import com.androlua.AsyncTaskX;

import org.luaj.LuaError;
import org.luaj.LuaString;
import org.luaj.LuaValue;
import com.osfans.trime.BuildConfig;

import java.io.BufferedReader;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.io.UnsupportedEncodingException;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.Charset;
import java.security.KeyManagementException;
import java.security.NoSuchAlgorithmException;
import java.security.cert.CertificateException;
import java.security.cert.X509Certificate;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

import javax.net.ssl.HostnameVerifier;
import javax.net.ssl.HttpsURLConnection;
import javax.net.ssl.SSLContext;
import javax.net.ssl.SSLSession;
import javax.net.ssl.TrustManager;
import javax.net.ssl.X509TrustManager;

public class Http {
    static {
        try {
            SSLContext sslcontext = null;
            sslcontext = SSLContext.getInstance("SSL");
            sslcontext.init(null, new TrustManager[]{new X509TrustManager() {
                @Override
                public void checkClientTrusted(X509Certificate[] chain, String authType) throws CertificateException {

                }

                @Override
                public void checkServerTrusted(X509Certificate[] chain, String authType) throws CertificateException {

                }

                @Override
                public X509Certificate[] getAcceptedIssuers() {
                    return new X509Certificate[0];
                }
            }}, new java.security.SecureRandom());

            HostnameVerifier ignoreHostnameVerifier = new HostnameVerifier() {
                public boolean verify(String s, SSLSession sslsession) {
                    //这块也不用有啥逻辑，确认结果是true就行
                    return true;
                }
            };
            HttpsURLConnection.setDefaultHostnameVerifier(ignoreHostnameVerifier);
            HttpsURLConnection.setDefaultSSLSocketFactory(sslcontext.getSocketFactory());
        } catch (NoSuchAlgorithmException | KeyManagementException e) {
            e.printStackTrace();
        }


    }

    private static HashMap<String, String> sHeader;

    public static void setHeader(HashMap<String, String> header) {
        sHeader = header;
    }

    public static void setUserAgent(String userAgent) {
        if (sHeader == null)
            sHeader = new HashMap<>();
        sHeader.put("User-Agent", userAgent);
    }

   /* static {
        setUserAgent("Mozilla/5.0 (Linux; Android 8.0.0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/63.0.3239.111 Mobile Safari/537.36 EdgA/41.0.0.1722");
    }*/

    public static HashMap<String, String> getHeader() {
        return sHeader;
    }

    public static HttpTask get(String url, LuaValue callback) {
        Http.HttpTask task = new HttpTask(url, "GET", null, null, null, callback);
        task.execute();
        return task;
    }

    public static HttpTask get(String url, HashMap<String, String> header, LuaValue callback) {
        Http.HttpTask task = new HttpTask(url, "GET", null, null, header, callback);
        task.execute();
        return task;
    }

    public static HttpTask get(String url, String cookie, HashMap<String, String> header, LuaValue callback) {
        Http.HttpTask task = cookie.matches("[\\w\\-\\.:]+") && Charset.isSupported(cookie) ? new HttpTask(url, "GET", null, cookie, header, callback) : new HttpTask(url, "GET", cookie, null, header, callback);
        task.execute();
        return task;
    }

    public static HttpTask get(String url, String cookie, LuaValue callback) {
        Http.HttpTask task = cookie.matches("[\\w\\-\\.:]+") && Charset.isSupported(cookie) ? new HttpTask(url, "GET", null, cookie, null, callback) : new HttpTask(url, "GET", cookie, null, null, callback);
        task.execute();
        return task;
    }

    public static HttpTask get(String url, String cookie, String charset, LuaValue callback) {
        Http.HttpTask task = new HttpTask(url, "GET", cookie, charset, null, callback);
        task.execute();
        return task;
    }

    public static HttpTask get(String url, String cookie, String charset, HashMap<String, String> header, LuaValue callback) {
        Http.HttpTask task = new HttpTask(url, "GET", cookie, charset, header, callback);
        task.execute();
        return task;
    }

    public static HttpTask download(String url, String data, LuaValue callback) {
        Http.HttpTask task = new HttpTask(url, "GET", null, null, null, callback);
        task.execute(data);
        return task;
    }

    public static HttpTask download(String url, String data, HashMap<String, String> header, LuaValue callback) {
        Http.HttpTask task = new HttpTask(url, "GET", null, null, header, callback);
        task.execute(data);
        return task;
    }

    public static HttpTask download(String url, String data, String cookie, LuaValue callback) {
        Http.HttpTask task = new HttpTask(url, "GET", cookie, null, null, callback);
        task.execute(data);
        return task;
    }

    public static HttpTask download(String url, String data, String cookie, HashMap<String, String> header, LuaValue callback) {
        Http.HttpTask task = new HttpTask(url, "GET", cookie, null, header, callback);
        task.execute(data);
        return task;
    }


    public static HttpTask delete(String url, LuaValue callback) {
        Http.HttpTask task = new HttpTask(url, "DELETE", null, null, null, callback);
        task.execute();
        return task;
    }

    public static HttpTask delete(String url, HashMap<String, String> header, LuaValue callback) {
        Http.HttpTask task = new HttpTask(url, "DELETE", null, null, header, callback);
        task.execute();
        return task;
    }

    public static HttpTask delete(String url, String cookie, HashMap<String, String> header, LuaValue callback) {
        Http.HttpTask task = cookie.matches("[\\w\\-\\.:]+") && Charset.isSupported(cookie) ? new HttpTask(url, "DELETE", null, cookie, header, callback) : new HttpTask(url, "DELETE", cookie, null, header, callback);
        task.execute();
        return task;
    }

    public static HttpTask delete(String url, String cookie, LuaValue callback) {
        Http.HttpTask task = cookie.matches("[\\w\\-\\.:]+") && Charset.isSupported(cookie) ? new HttpTask(url, "DELETE", null, cookie, null, callback) : new HttpTask(url, "DELETE", cookie, null, null, callback);
        task.execute();
        return task;
    }

    public static HttpTask delete(String url, String cookie, String charset, LuaValue callback) {
        Http.HttpTask task = new HttpTask(url, "DELETE", cookie, charset, null, callback);
        task.execute();
        return task;
    }

    public static HttpTask delete(String url, String cookie, String charset, HashMap<String, String> header, LuaValue callback) {
        Http.HttpTask task = new HttpTask(url, "DELETE", cookie, charset, header, callback);
        task.execute();
        return task;
    }


    public static HttpTask post(String url, String data, LuaValue callback) {
        Http.HttpTask task = new HttpTask(url, "POST", null, null, null, callback);
        task.execute(data);
        return task;
    }

    public static HttpTask post(String url, String data, HashMap<String, String> header, LuaValue callback) {
        Http.HttpTask task = new HttpTask(url, "POST", null, null, header, callback);
        task.execute(data);
        return task;
    }

    public static HttpTask post(String url, String data, String cookie, LuaValue callback) {
        Http.HttpTask task = cookie.matches("[\\w\\-.:]+") && Charset.isSupported(cookie) ? new HttpTask(url, "POST", null, cookie, null, callback) : new HttpTask(url, "POST", cookie, null, null, callback);
        task.execute(data);
        return task;
    }

    public static HttpTask post(String url, String data, String cookie, HashMap<String, String> header, LuaValue callback) {
        Http.HttpTask task = cookie.matches("[\\w\\-.:]+") && Charset.isSupported(cookie) ? new HttpTask(url, "POST", null, cookie, header, callback) : new HttpTask(url, "POST", cookie, null, header, callback);
        task.execute(data);
        return task;
    }

    public static HttpTask post(String url, String data, String cookie, String charset, LuaValue callback) {
        Http.HttpTask task = new HttpTask(url, "POST", cookie, charset, null, callback);
        task.execute(data);
        return task;
    }

    public static HttpTask post(String url, String data, String cookie, String charset, HashMap<String, String> header, LuaValue callback) {
        Http.HttpTask task = new HttpTask(url, "POST", cookie, charset, header, callback);
        task.execute(data);
        return task;
    }

    public static HttpTask post(String url, HashMap<String, String> data, LuaValue callback) {
        return post(url, formatMap(data), callback);
    }

    public static HttpTask post(String url, HashMap<String, String> data, String cookie, LuaValue callback) {
        return post(url, formatMap(data), cookie, callback);
    }

    public static HttpTask post(String url, HashMap<String, String> data, String cookie, HashMap<String, String> header, LuaValue callback) {
        return post(url, formatMap(data), cookie, header, callback);
    }

    public static HttpTask post(String url, HashMap<String, String> data, String cookie, String charset, LuaValue callback) {
        return post(url, formatMap(data), cookie, charset, callback);
    }

    public static HttpTask post(String url, HashMap<String, String> data, String cookie, String charset, HashMap<String, String> header, LuaValue callback) {
        return post(url, formatMap(data), cookie, charset, header, callback);
    }

    private static String formatMap(HashMap<String, String> data) {
        StringBuilder buf = new StringBuilder();
        for (Map.Entry<String, String> entry : data.entrySet()) {
            buf.append(entry.getKey()).append("=").append(entry.getValue()).append("&");
        }
        if (!data.isEmpty())
            buf.deleteCharAt(buf.length() - 1);
        return buf.toString();
    }


    private final static String boundary = "----qwertyuiopasdfghjklzxcvbnm";

    public static HttpTask post(String url, HashMap<String, String> data, HashMap<String, String> file, LuaValue callback) {
        return post(url, data, file, null, null, null, callback);
    }

    public static HttpTask post(String url, HashMap<String, String> data, HashMap<String, String> file, String cookie, LuaValue callback) {
        return post(url, data, file, cookie, new HashMap<String, String>(), callback);
    }

    public static HttpTask post(String url, HashMap<String, String> data, HashMap<String, String> file, HashMap<String, String> header, LuaValue callback) {
        return post(url, data, file, null, header, callback);
    }

    public static HttpTask post(String url, HashMap<String, String> data, HashMap<String, String> file, String cookie, HashMap<String, String> header, LuaValue callback) {
        return cookie.matches("[\\w\\-.:]+") && Charset.isSupported(cookie) ? post(url, data, file, cookie, null, header, callback) : post(url, data, file, null, cookie, header, callback);
    }

    public static HttpTask post(String url, HashMap<String, String> data, HashMap<String, String> file, String cookie, String charset, LuaValue callback) {
        return post(url, data, file, cookie, charset, null, callback);
    }

    public static HttpTask post(String url, HashMap<String, String> data, HashMap<String, String> file, String cookie, String charset, HashMap<String, String> header, LuaValue callback) {
        if (header == null)
            header = new HashMap<>();
        header.put("Content-Type", "multipart/form-data;boundary=" + boundary);
        Http.HttpTask task = new HttpTask(url, "POST", cookie, charset, header, callback);
        task.execute(new Object[]{formatMultiDate(data, file, charset)});
        return task;
    }

    private static String getType(String file) {
        int lastDot = file.lastIndexOf(46);
        if (lastDot >= 0) {
            String extension = file.substring(lastDot + 1);
            String mime = MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension);
            if (mime != null) {
                return mime;
            }
        }
        return "application/octet-stream";
    }

    private static byte[] formatMultiDate(HashMap<String, String> data, HashMap<String, String> file, String charset) {
        if (charset == null)
            charset = "UTF-8";
        ByteArrayOutputStream buff = new ByteArrayOutputStream();
        for (Map.Entry<String, String> entry : data.entrySet()) {
            try {
                buff.write(String.format("--%s\r\nContent-Disposition:form-data;name=\"%s\"\r\n\r\n%s\r\n", boundary, entry.getKey(), entry.getValue()).getBytes(charset));
            } catch (IOException e) {
                if(BuildConfig.DEBUG)
			        e.printStackTrace();
            }
        }

        for (Map.Entry<String, String> entry : file.entrySet()) {
            try {
                buff.write(String.format("--%s\r\nContent-Disposition:form-data;name=\"%s\";filename=\"%s\"\r\nContent-Type:%s\r\n\r\n", boundary, entry.getKey(), entry.getValue(),getType(entry.getValue())).getBytes(charset));
                buff.write(LuaUtil.readAll(new FileInputStream(entry.getValue())));
                buff.write("\r\n".getBytes(charset));
            } catch (IOException e) {
                if(BuildConfig.DEBUG)
			        e.printStackTrace();
            }
        }
        try {
            buff.write(String.format("--%s--\r\n", boundary).getBytes(charset));
        } catch (IOException e) {
            if(BuildConfig.DEBUG)
			    e.printStackTrace();
        }

        return buff.toByteArray();
    }


    public static HttpTask put(String url, String data, LuaValue callback) {
        Http.HttpTask task = new HttpTask(url, "PUT", null, null, null, callback);
        task.execute(data);
        return task;
    }

    public static HttpTask put(String url, String data, HashMap<String, String> header, LuaValue callback) {
        Http.HttpTask task = new HttpTask(url, "PUT", null, null, header, callback);
        task.execute(data);
        return task;
    }

    public static HttpTask put(String url, String data, String cookie, LuaValue callback) {
        Http.HttpTask task = cookie.matches("[\\w\\-\\.:]+") && Charset.isSupported(cookie) ? new HttpTask(url, "PUT", null, cookie, null, callback) : new HttpTask(url, "PUT", cookie, null, null, callback);
        task.execute(data);
        return task;
    }

    public static HttpTask put(String url, String data, String cookie, HashMap<String, String> header, LuaValue callback) {
        Http.HttpTask task = cookie.matches("[\\w\\-\\.:]+") && Charset.isSupported(cookie) ? new HttpTask(url, "PUT", null, cookie, header, callback) : new HttpTask(url, "PUT", cookie, null, header, callback);
        task.execute(data);
        return task;
    }

    public static HttpTask put(String url, String data, String cookie, String charset, LuaValue callback) {
        Http.HttpTask task = new HttpTask(url, "PUT", cookie, charset, null, callback);
        task.execute(data);
        return task;
    }

    public static HttpTask put(String url, String data, String cookie, String charset, HashMap<String, String> header, LuaValue callback) {
        Http.HttpTask task = new HttpTask(url, "PUT", cookie, charset, header, callback);
        task.execute(data);
        return task;
    }

    /**
     * 流式上传本地文件（WebDAV PUT）。
     * 直接把 File 交给 AsyncTaskX，由 HttpTask 边读边写：
     *  - 内存恒定（64KB 缓冲），与文件大小无关
     *  - 不经过 LuaString -> Java String 的 UTF-8 往返，二进制安全
     * 需配合下方 HttpTask 中的 streaming 分支使用。
     */
    public static HttpTask putFile(String url, String path, HashMap<String, String> header, LuaValue callback) {
        Http.HttpTask task = new HttpTask(url, "PUT", null, null, header, callback);
        task.execute(new File(path));
        return task;
    }


    public static class HttpTask extends AsyncTaskX<Object, Object, Object> {

        private String mUrl;

        private LuaValue mCallback;

        private byte[] mData;

        private String mCharset;

        private String mOutCharset;

        private String mCookie;

        private HashMap<String, String> mHeader;

        private String mMethod;


        public HttpTask(String url, String method, String cookie, String charset, HashMap<String, String> header, LuaValue callback) {
            mUrl = url;
            mMethod = method;
            mCookie = cookie;
            mCharset = charset;
            mOutCharset=charset;
            mHeader = header;
            mCallback = callback;
        }


        @Override
        protected Object doInBackground(Object[] p1) {
            // TODO: Implement this method
            try {
                URL url = new URL(mUrl);

                HttpURLConnection conn = (HttpURLConnection) url.openConnection();
                conn.setConnectTimeout(6000);
                HttpURLConnection.setFollowRedirects(true);
                conn.setDoInput(true);
                conn.setRequestProperty("Accept-Language", "zh-cn,zh;q=0.5");

                if (mCharset == null)
                    mCharset = "UTF-8";
                conn.setRequestProperty("Accept-Charset", mCharset);

                if (mCookie != null)
                    conn.setRequestProperty("Cookie", mCookie);

                if (sHeader != null) {
                    Set<Map.Entry<String, String>> entries = sHeader.entrySet();
                    for (Map.Entry<String, String> entry : entries) {
                        conn.setRequestProperty(entry.getKey(), entry.getValue());
                    }
                }

                if (mHeader != null) {
                    Set<Map.Entry<String, String>> entries = mHeader.entrySet();
                    for (Map.Entry<String, String> entry : entries) {
                        conn.setRequestProperty(entry.getKey(), entry.getValue());
                    }
                }

                if (mMethod != null)
                    conn.setRequestMethod(mMethod);

                boolean streaming = (p1.length == 1 && p1[0] instanceof File);
                if (!"GET".equals(mMethod) && p1.length != 0 && !streaming) {
                    mData = formatData(p1);

                    conn.setDoOutput(true);
                    conn.setRequestProperty("Content-length", "" + mData.length);
                } else if (streaming) {
                    // 边读边写：不再把整个文件读进 byte[]，内存与文件大小无关
                    conn.setDoOutput(true);
                    long len = ((File) p1[0]).length();
                    if (len <= Integer.MAX_VALUE)
                        conn.setFixedLengthStreamingMode((int) len);
                    else
                        conn.setChunkedStreamingMode(64 * 1024);
                }

                conn.connect();

                //download
                if ("GET".equals(mMethod) && p1.length != 0) {
                    File f = new File((String) p1[0]);
                    if (!f.getParentFile().exists())
                        //noinspection ResultOfMethodCallIgnored
                        f.getParentFile().mkdirs();
                    FileOutputStream os = new FileOutputStream(f);
                    InputStream is = conn.getInputStream();
                    LuaUtil.copyFile(is, os);
                    return new Object[]{conn.getResponseCode(), p1[0], conn.getHeaderFields()};
                }

                //post upload
                if (p1.length != 0) {
                    OutputStream os = conn.getOutputStream();
                    if (streaming) {
                        FileInputStream fis = new FileInputStream((File) p1[0]);
                        byte[] buf = new byte[64 * 1024];
                        int n;
                        while (-1 != (n = fis.read(buf)))
                            os.write(buf, 0, n);
                        fis.close();
                    } else {
                        os.write(mData);
                    }
                    os.flush();
                    os.close();
                }

                int code = conn.getResponseCode();
                Map<String, List<String>> hs = conn.getHeaderFields();
                String encoding = conn.getContentEncoding();
                List<String> cs = hs.get("Set-Cookie");
                StringBuilder cok = new StringBuilder();
                if (cs != null) {
                    for (String s : cs) {
                        cok.append(s).append(";");
                    }
                }

                List<String> ct = hs.get("Content-Type");
                if (ct != null) {
                    for (String s : ct) {
                        int idx = s.indexOf("charset");
                        if (idx != -1) {
                            idx = s.indexOf("=", idx);
                            if (idx != -1) {
                                int idx2 = s.indexOf(";", idx);
                                if (idx2 == -1)
                                    idx2 = s.length();
                                mCharset = s.substring(idx + 1, idx2);
                                break;
                            }
                        }
                    }
                }

                /*if(mOutCharset==null){
                   try {
                        InputStream is = conn.getInputStream();
                        byte[] reader = LuaUtil.readAll(is);
                        is.close();
                        LuaString buf = new LuaString(reader,0,reader.length);
                        return new Object[]{code, buf, cok.toString(), hs};
                    } catch (Exception e) {
                        if(BuildConfig.DEBUG)
			    e.printStackTrace();
                    }
                }*/
                StringBuilder buf = new StringBuilder();
                try {
                    InputStream is = conn.getInputStream();
                    BufferedReader reader = new BufferedReader(new InputStreamReader(is, mCharset));
                    String line = reader.readLine();
                    if (line != null)
                        buf.append(line);
                    while ((line = reader.readLine()) != null && !isCancelled())
                        buf.append('\n').append(line);
                    is.close();
                } catch (Exception e) {
                    if(BuildConfig.DEBUG)
			            e.printStackTrace();
                }
                InputStream is = conn.getErrorStream();
                if (is != null) {
                    BufferedReader reader = new BufferedReader(new InputStreamReader(is, mCharset));
                    String line = reader.readLine();
                    if (line != null)
                        buf.append(line);
                    while ((line = reader.readLine()) != null && !isCancelled())
                        buf.append('\n').append(line);
                    is.close();
                }
                return new Object[]{code, new String(buf), cok.toString(), hs};
            } catch (Exception e) {
                if(BuildConfig.DEBUG)
			        e.printStackTrace();
                return new Object[]{-1, e.getMessage()};
            }

        }

        private byte[] formatData(Object[] p1) throws UnsupportedEncodingException, IOException {
            // TODO: Implement this method
            byte[] bs = null;
            if (p1.length == 1) {
                Object obj = p1[0];
                if (obj instanceof String)
                    bs = ((String) obj).getBytes(mCharset);
                else if (obj.getClass().getComponentType() == byte.class)
                    bs = (byte[]) obj;
                else if (obj instanceof File)
                    bs = LuaUtil.readAll(new FileInputStream((File) obj));
                else if (obj instanceof Map)
                    bs = formatData((Map<String, String>) obj);
            }
            return bs;
        }

        private byte[] formatData(Map<String, String> obj) throws UnsupportedEncodingException {
            // TODO: Implement this method
            StringBuilder buf = new StringBuilder();
            Set<Map.Entry<String, String>> entries = obj.entrySet();
            for (Map.Entry<String, String> entry : entries) {
                buf.append(entry.getKey()).append("=").append(entry.getValue()).append("&");
            }
            return buf.toString().getBytes(mCharset);
        }


        public boolean cancel() {
            // TODO: Implement this method
            return super.cancel(true);
        }


        @Override
        protected void onPostExecute(Object result) {
            // TODO: Implement this method
            if (isCancelled())
                return;
            try {
                mCallback.jcall((Object[]) result);
            } catch (LuaError e) {
                android.util.Log.i("lua", e.getMessage());
            }
        }

    }
}
