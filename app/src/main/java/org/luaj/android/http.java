package org.luaj.android;

import android.webkit.MimeTypeMap;

import com.androlua.LuaUtil;
import com.osfans.trime.BuildConfig;

import org.luaj.LuaValue;
import org.luaj.Varargs;
import org.luaj.lib.jse.CoerceJavaToLua;

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
import java.util.Locale;
import java.util.Map;
import java.util.Set;

import javax.net.ssl.HostnameVerifier;
import javax.net.ssl.HttpsURLConnection;
import javax.net.ssl.SSLContext;
import javax.net.ssl.SSLSession;
import javax.net.ssl.TrustManager;
import javax.net.ssl.X509TrustManager;


public class http {
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

    public static HashMap<String, String> getHeader() {
        return sHeader;
    }


    public static HttpResult get(String url) {
        LuaHttp task = new LuaHttp(url, "GET", null, null, null);
        return task.connection();
    }

    public static HttpResult get(String url, HashMap<String, String> header) {
        LuaHttp task = new LuaHttp(url, "GET", null, null, header);

        return task.connection();
    }

    public static HttpResult get(String url, String cookie, HashMap<String, String> header) {
        LuaHttp task = cookie.matches("[\\w\\-]+") && Charset.isSupported(cookie) ? new LuaHttp(url, "GET", null, cookie, header) : new LuaHttp(url, "GET", cookie, null, header);

        return task.connection();
    }

    public static HttpResult get(String url, String cookie) {
        LuaHttp task = cookie.matches("[\\w\\-]+") && Charset.isSupported(cookie) ? new LuaHttp(url, "GET", null, cookie, null) : new LuaHttp(url, "GET", cookie, null, null);

        return task.connection();
    }

    public static HttpResult get(String url, String cookie, String charset) {
        LuaHttp task = new LuaHttp(url, "GET", cookie, charset, null);

        return task.connection();
    }

    public static HttpResult get(String url, String cookie, String charset, HashMap<String, String> header) {
        LuaHttp task = new LuaHttp(url, "GET", cookie, charset, header);

        return task.connection();
    }

    public static HttpResult download(String url, String data) {
        LuaHttp task = new LuaHttp(url, "GET", null, null, null);

        return task.connection(data);
    }

    public static HttpResult download(String url, String data, HashMap<String, String> header) {
        LuaHttp task = new LuaHttp(url, "GET", null, null, header);

        return task.connection(data);
    }

    public static HttpResult download(String url, String data, String cookie) {
        LuaHttp task = new LuaHttp(url, "GET", cookie, null, null);

        return task.connection(data);
    }

    public static HttpResult download(String url, String data, String cookie, HashMap<String, String> header) {
        LuaHttp task = new LuaHttp(url, "GET", cookie, null, header);

        return task.connection(data);
    }


    public static HttpResult delete(String url) {
        LuaHttp task = new LuaHttp(url, "DELETE", null, null, null);

        return task.connection();
    }

    public static HttpResult delete(String url, HashMap<String, String> header) {
        LuaHttp task = new LuaHttp(url, "DELETE", null, null, header);

        return task.connection();
    }

    public static HttpResult delete(String url, String cookie, HashMap<String, String> header) {
        LuaHttp task = cookie.matches("[\\w\\-]+") && Charset.isSupported(cookie) ? new LuaHttp(url, "DELETE", null, cookie, header) : new LuaHttp(url, "DELETE", cookie, null, header);

        return task.connection();
    }

    public static HttpResult delete(String url, String cookie) {
        LuaHttp task = cookie.matches("[\\w\\-]+") && Charset.isSupported(cookie) ? new LuaHttp(url, "DELETE", null, cookie, null) : new LuaHttp(url, "DELETE", cookie, null, null);

        return task.connection();
    }

    public static HttpResult delete(String url, String cookie, String charset) {
        LuaHttp task = new LuaHttp(url, "DELETE", cookie, charset, null);

        return task.connection();
    }

    public static HttpResult delete(String url, String cookie, String charset, HashMap<String, String> header) {
        LuaHttp task = new LuaHttp(url, "DELETE", cookie, charset, header);

        return task.connection();
    }


    public static HttpResult post(String url, String data) {
        LuaHttp task = new LuaHttp(url, "POST", null, null, null);

        return task.connection(data);
    }

    public static HttpResult post(String url, String data, HashMap<String, String> header) {
        LuaHttp task = new LuaHttp(url, "POST", null, null, header);

        return task.connection(data);
    }

    public static HttpResult post(String url, String data, String cookie) {
        LuaHttp task = cookie.matches("[\\w\\-]+") && Charset.isSupported(cookie) ? new LuaHttp(url, "POST", null, cookie, null) : new LuaHttp(url, "POST", cookie, null, null);

        return task.connection(data);
    }

    public static HttpResult post(String url, String data, String cookie, HashMap<String, String> header) {
        LuaHttp task = cookie.matches("[\\w\\-]+") && Charset.isSupported(cookie) ? new LuaHttp(url, "POST", null, cookie, header) : new LuaHttp(url, "POST", cookie, null, header);

        return task.connection(data);
    }

    public static HttpResult post(String url, String data, String cookie, String charset) {
        LuaHttp task = new LuaHttp(url, "POST", cookie, charset, null);

        return task.connection(data);
    }

    public static HttpResult post(String url, String data, String cookie, String charset, HashMap<String, String> header) {
        LuaHttp task = new LuaHttp(url, "POST", cookie, charset, header);

        return task.connection(data);
    }


    public static HttpResult post(String url, HashMap<String, String> data) {
        return post(url, formatMap(data));
    }

    public static HttpResult post(String url, HashMap<String, String> data, String cookie) {
        return post(url, formatMap(data), cookie);
    }

    public static HttpResult post(String url, HashMap<String, String> data, String cookie, HashMap<String, String> header) {
        return post(url, formatMap(data), cookie, header);
    }

    public static HttpResult post(String url, HashMap<String, String> data, String cookie, String charset) {
        return post(url, formatMap(data), cookie, charset);
    }

    public static HttpResult post(String url, HashMap<String, String> data, String cookie, String charset, HashMap<String, String> header) {
        return post(url, formatMap(data), cookie, charset, header);
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

    public static HttpResult post(String url, HashMap<String, String> data, HashMap<String, String> file) {
        return post(url, data, file, null, null, null);
    }

    public static HttpResult post(String url, HashMap<String, String> data, HashMap<String, String> file, String cookie) {
        return post(url, data, file, cookie, new HashMap<String, String>());
    }

    public static HttpResult post(String url, HashMap<String, String> data, HashMap<String, String> file, HashMap<String, String> header) {
        return post(url, data, file, null, header);
    }

    public static HttpResult post(String url, HashMap<String, String> data, HashMap<String, String> file, String cookie, HashMap<String, String> header) {
        return cookie.matches("[\\w\\-.:]+") && Charset.isSupported(cookie) ? post(url, data, file, cookie, null, header) : post(url, data, file, null, cookie, header);
    }

    public static HttpResult post(String url, HashMap<String, String> data, HashMap<String, String> file, String cookie, String charset) {
        return post(url, data, file, cookie, charset, null);
    }

    public static HttpResult post(String url, HashMap<String, String> data, HashMap<String, String> file, String cookie, String charset, HashMap<String, String> header) {
        if (header == null)
            header = new HashMap<>();
        header.put("Content-Type", "multipart/form-data;boundary=" + boundary);
        LuaHttp task = new LuaHttp(url, "POST", cookie, charset, header);
        return task.connection(new Object[]{formatMultiDate(data, file, charset)});
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
    
    public static HttpResult put(String url, String data) {
        LuaHttp task = new LuaHttp(url, "PUT", null, null, null);

        return task.connection(data);
    }

    public static HttpResult put(String url, String data, HashMap<String, String> header) {
        LuaHttp task = new LuaHttp(url, "PUT", null, null, header);

        return task.connection(data);
    }

    public static HttpResult put(String url, String data, String cookie) {
        LuaHttp task = cookie.matches("[\\w\\-]+") && Charset.isSupported(cookie) ? new LuaHttp(url, "PUT", null, cookie, null) : new LuaHttp(url, "PUT", cookie, null, null);

        return task.connection(data);
    }

    public static HttpResult put(String url, String data, String cookie, HashMap<String, String> header) {
        LuaHttp task = cookie.matches("[\\w\\-]+") && Charset.isSupported(cookie) ? new LuaHttp(url, "PUT", null, cookie, header) : new LuaHttp(url, "PUT", cookie, null, header);

        return task.connection(data);
    }

    public static HttpResult put(String url, String data, String cookie, String charset) {
        LuaHttp task = new LuaHttp(url, "PUT", cookie, charset, null);

        return task.connection(data);
    }

    public static HttpResult put(String url, String data, String cookie, String charset, HashMap<String, String> header) {
        LuaHttp task = new LuaHttp(url, "PUT", cookie, charset, header);

        return task.connection(data);
    }


    public static class LuaHttp {

        private String mUrl;

        private byte[] mData;

        private String mCharset;

        private String mCookie;

        private HashMap<String, String> mHeader;

        private String mMethod;

        public LuaHttp(String url, String method, String cookie, String charset, HashMap<String, String> header) {
            mUrl = url;
            mMethod = method;
            mCookie = cookie;
            mCharset = charset;
            mHeader = header;
        }

        public HttpResult connection(Object... p1) {
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

                if (!"GET".equals(mMethod) && p1.length != 0) {
                    mData = formatData(p1);

                    conn.setDoOutput(true);
                    conn.setRequestProperty("Content-length", "" + mData.length);
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
                    return new HttpResult(conn.getResponseCode(), f.getAbsolutePath(), null, conn.getHeaderFields());
                }

                //post upload
                if (p1.length != 0) {
                    OutputStream os = conn.getOutputStream();
                    os.write(mData);
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

                if(mCharset==null){
                    mCharset="UTF-8";
                }

                StringBuilder buf = new StringBuilder();
                try {
                    InputStream is = conn.getInputStream();
                    BufferedReader reader = new BufferedReader(new InputStreamReader(is, mCharset));
                    String line = reader.readLine();
                    if (line != null)
                        buf.append(line);
                    while ((line = reader.readLine()) != null)
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
                    while ((line = reader.readLine()) != null)
                        buf.append('\n').append(line);
                    is.close();
                }
                return new HttpResult(code, new String(buf), cok.toString(), hs);
            } catch (Exception e) {
                if(BuildConfig.DEBUG)
			    e.printStackTrace();
                return new HttpResult(-1, e.getMessage(), null, null);
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
                    bs = formatData((Map) obj);
            }
            return bs;
        }

        private byte[] formatData(Map obj) throws UnsupportedEncodingException {
            // TODO: Implement this method
            StringBuilder buf = new StringBuilder();
            Set<Map.Entry<String, String>> entries = mHeader.entrySet();
            for (Map.Entry<String, String> entry : entries) {
                buf.append(entry.getKey()).append("=").append(entry.getValue()).append("&");
            }
            return buf.toString().getBytes(mCharset);
        }
    }

    public interface HttpCallback {
        public void onDone(HttpResult result);
    }

    public static class HttpResult extends Varargs {
        public int code;
        public String text;
        public String cookie;
        public Map<String, List<String>> header;

        public HttpResult(int code,
                          String text,
                          String cookie,
                          Map<String, List<String>> header) {

            this.code = code;
            this.text = text;
            this.cookie = cookie;
            this.header = header;
        }

        @Override
        public LuaValue arg(int i) {
            switch (i){
                case 0:
                    return LuaValue.valueOf(text);
                case 1:
                    return LuaValue.valueOf(cookie);
                case 2:
                    return LuaValue.valueOf(code);
                case 3:
                    return CoerceJavaToLua.coerce(header);

            }
            return null;
        }

        @Override
        public int narg() {
            return 0;
        }

        @Override
        public LuaValue arg1() {
            return null;
        }

        @Override
        public String toString() {
            return text;
        }

        @Override
        public Varargs subargs(int start) {
            return null;
        }
    }
}
