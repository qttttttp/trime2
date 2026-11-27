package com.androlua;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;
import com.osfans.trime.BuildConfig;

import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStreamWriter;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.Iterator;
import java.util.List;
import java.util.Map;

/**
 * Created by Administrator on 2017/04/22 0022.
 */

public class JsonUtil {
    private static Map<String, Map<String, String>> cache = new HashMap<>();

    public static Map<String, String> read(String path) {
        Map<String, String> map = cache.get(path);
        if (map != null)
            return map;
        map = new HashMap<>();
        try {
            InputStream stream = new FileInputStream(path);
            BufferedReader reader = new BufferedReader(new InputStreamReader(stream, "UTF-8"));
            StringBuilder stringBuilder = new StringBuilder();
            String input;
            while ((input = reader.readLine()) != null) {
                stringBuilder.append(input);
            }
            stream.close();

            JSONObject letters = new JSONObject(stringBuilder.toString());
            Iterator<?> keys = letters.keys();
            while (keys.hasNext()) {
                String letter = (String) keys.next();
                map.put(letter, letters.getString(letter));
            }
        } catch (java.io.IOException | JSONException ignored) {
        }
        cache.put(path, map);
        return map;
    }

    public static Map<String, String> read2(String path) {
        Map<String, String> map = new HashMap<>();
        if (!new File(path).exists())
            return map;
        try {
            InputStream stream = new FileInputStream(path);
            BufferedReader reader = new BufferedReader(new InputStreamReader(stream, "UTF-8"));
            StringBuilder stringBuilder = new StringBuilder();
            String input;
            while ((input = reader.readLine()) != null) {
                stringBuilder.append(input);
            }
            stream.close();

            JSONObject letters = new JSONObject(stringBuilder.toString());
            Iterator<?> keys = letters.keys();
            while (keys.hasNext()) {
                String letter = (String) keys.next();
                map.put(letter, letters.getString(letter));
            }
        } catch (java.io.IOException | JSONException ignored) {
        }
        return map;
    }

    public static void save(String path, Map<String, String> map) {
        JSONObject json = new JSONObject(map);
        try {
            BufferedWriter writer = new BufferedWriter(new OutputStreamWriter(new FileOutputStream(path), "UTF-8"));
            writer.write(json.toString(4));
            writer.close();
        } catch (Exception e) {
            if(BuildConfig.DEBUG)
			    e.printStackTrace();
        }
    }

    public static void save(String path, JSONObject json) {
        try {
            BufferedWriter writer = new BufferedWriter(new OutputStreamWriter(new FileOutputStream(path), "UTF-8"));
            writer.write(json.toString(4));
            writer.close();
        } catch (Exception e) {
            if(BuildConfig.DEBUG)
			    e.printStackTrace();
        }
    }

    public static ArrayList<String> load(String path) {
        ArrayList<String> map = new ArrayList<>();
        if (!new File(path).exists())
            return map;
        try {
            InputStream stream = new FileInputStream(path);
            BufferedReader reader = new BufferedReader(new InputStreamReader(stream, "UTF-8"));
            StringBuilder stringBuilder = new StringBuilder();
            String input;
            while ((input = reader.readLine()) != null) {
                stringBuilder.append(input);
            }
            stream.close();
            JSONArray letters = new JSONArray(stringBuilder.toString());
            int len = letters.length();
            for (int i = 0; i < len; i++) {
                map.add(letters.getString(i));
            }
        } catch (java.io.IOException | JSONException ignored) {
        }
        return map;
    }


    public static void save(String path, List<String> map) {
        JSONArray json = new JSONArray(map);
        try {
            BufferedWriter writer = new BufferedWriter(new OutputStreamWriter(new FileOutputStream(path), "UTF-8"));
            writer.write(json.toString(4));
            writer.close();
        } catch (Exception e) {
            if(BuildConfig.DEBUG)
			    e.printStackTrace();
        }
    }

    public static void saveText(String path, List<String> map) {
        try {
            BufferedWriter writer = new BufferedWriter(new OutputStreamWriter(new FileOutputStream(path), "UTF-8"));
            for (String t : map) {
                writer.write(t);
                writer.newLine();
            }
            writer.close();
        } catch (IOException e) {
            if(BuildConfig.DEBUG)
			    e.printStackTrace();
        }
    }

    public static void reset() {
        cache.clear();
    }

    public static ArrayList<HistoryData> loadHistoryData(String path) {
        ArrayList<HistoryData> list = new ArrayList<>();
        if (!new File(path).exists())
            return list;
        try {
            InputStream stream = new FileInputStream(new File(path));
            BufferedReader reader = new BufferedReader(new InputStreamReader(stream, "UTF-8"));
            StringBuilder stringBuilder = new StringBuilder();
            String input;
            while ((input = reader.readLine()) != null) {
                stringBuilder.append(input);
            }
            stream.close();
            try {
                JSONArray json = new JSONObject(stringBuilder.toString()).getJSONArray("history");
                int len = json.length();
                for (int i = 0; i < len; i++) {
                    list.add(new HistoryData(json.getJSONObject(i)));
                }
            } catch (JSONException e) {
                if(BuildConfig.DEBUG)
			        e.printStackTrace();
            }
        } catch (java.io.IOException e) {
            if(BuildConfig.DEBUG)
			    e.printStackTrace();
        }
        return list;
    }

    public static void saveHistoryData(String path, ArrayList<HistoryData> history) {
        JSONObject json = new JSONObject();
        JSONArray list = new JSONArray();
        try {
            for (HistoryData data : history) {
                list.put(data.toJson());
            }
            json.put("history", list);
        } catch (JSONException e) {
            if(BuildConfig.DEBUG)
			    e.printStackTrace();
        }
         try {
            BufferedWriter writer = new BufferedWriter(new OutputStreamWriter(new FileOutputStream(path), "UTF-8"));
            writer.write(json.toString(2));
            writer.close();
        } catch (Exception e) {
            if(BuildConfig.DEBUG)
			    e.printStackTrace();
        }
    }

    public static class HistoryData {
        private String mPath;
        private int mIdx;

        public HistoryData(JSONObject json) {
            mPath = json.optString("path");
            mIdx = json.optInt("idx");
        }

        public HistoryData(String path, int idx) {
            mPath = path;
            mIdx = idx;
        }

        public String getPath() {
            return mPath;
        }


        public int getIdx() {
            return mIdx;
        }

        public JSONObject toJson() {
            JSONObject j = new JSONObject();
            try {
                j.put("path",mPath);
                j.put("idx",mIdx);
            } catch (JSONException e) {
                if(BuildConfig.DEBUG)
			        e.printStackTrace();
            }
            return j;
        }
    }
}
