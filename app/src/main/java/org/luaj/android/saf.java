package org.luaj.android;

import android.content.Intent;
import android.net.Uri;
import android.provider.DocumentsContract;

import com.androlua.LuaActivity;
import com.androlua.LuaUtil;

import org.luaj.LuaFunction;
import org.luaj.LuaString;
import org.luaj.LuaValue;
import org.luaj.lib.jse.CoerceJavaToLua;

import java.io.FileNotFoundException;
import java.io.InputStream;
import java.io.OutputStream;
import androidx.documentfile.provider.DocumentFile;
public class saf {

    private final LuaActivity mActivity;
    private DocumentFile mDocumentFile;

    public saf(LuaActivity activity){
        mActivity=activity;
        String d = (String) mActivity.getSharedData("_DOCUMENT_TREE", null);
        if(d!=null){
            try {
                Uri uri = Uri.parse(d);
                mDocumentFile= DocumentFile.fromTreeUri(mActivity, uri);
            }catch (Exception e){
                e.printStackTrace();
            }
       }
    }

    public void list(LuaFunction function){
        if(mDocumentFile==null){
            select(new LuaFunction() {
                public LuaValue call(LuaValue arg1, LuaValue arg2) {
                    list(function);
                    return LuaValue.NONE;
                }
            });
        }
        DocumentFile[] list = mDocumentFile.listFiles();
        function.call(CoerceJavaToLua.coerce(list));
    }

    public DocumentFile get(){
        return mDocumentFile;
    }


    public void select(LuaFunction function){
        mActivity.openDocumentTree(new LuaFunction() {
            @Override
            public LuaValue call(LuaValue arg) {
                Intent intent=arg.touserdata(Intent.class);
                if(intent==null||intent.getData()==null){
                    function.call(LuaValue.NIL);
                    return LuaValue.NONE;
                }
                try {
                    mDocumentFile= DocumentFile.fromTreeUri(mActivity, intent.getData());
                    mActivity.setSharedData("_DOCUMENT_TREE",intent.getData().toString());
                    function.call(CoerceJavaToLua.coerce(intent), CoerceJavaToLua.coerce(mDocumentFile));
                } catch (Exception e) {
                    e.printStackTrace();
                }
                return LuaValue.NONE;
            }
        });
    }

    public void read(LuaFunction function){
        mActivity.getDocument("*/*", new LuaFunction() {
            @Override
            public LuaValue call(LuaValue arg) {
                Intent intent=arg.touserdata(Intent.class);
                if(intent==null||intent.getData()==null){
                    function.call(LuaValue.NIL);
                    return LuaValue.NONE;
                }
                try {
                    InputStream in = mActivity.getContentResolver().openInputStream(intent.getData());
                    byte[] bs = LuaUtil.readAll(in);
                    function.call(CoerceJavaToLua.coerce(intent), LuaString.valueOf(bs));
                } catch (Exception e) {
                    e.printStackTrace();
                }
                return LuaValue.NONE;
            }
        });
    }

    public void save(String name,LuaString bs, LuaFunction function){
        mActivity.createDocument("*/*",name, new LuaFunction() {
            @Override
            public LuaValue call(LuaValue arg) {
                Intent intent=arg.touserdata(Intent.class);
                if(intent==null||intent.getData()==null){
                    function.call(LuaValue.NIL);
                    return LuaValue.NONE;
                }
                try {
                    OutputStream out = mActivity.getContentResolver().openOutputStream(intent.getData());
                    LuaUtil.save(out,bs);
                    function.call(CoerceJavaToLua.coerce(intent));
                } catch (Exception e) {
                    e.printStackTrace();
                    function.call(CoerceJavaToLua.coerce(e.toString()));
                }
                return LuaValue.NONE;
            }
        });
    }

    public LuaValue read(String name){
        DocumentFile f = mDocumentFile.findFile(name);
        try {
            if(f!=null) {
                InputStream in = mActivity.getContentResolver().openInputStream(f.getUri());
                if(in!=null) {
                    byte[] bs = LuaUtil.readAll(in);
                    return LuaString.valueOf(bs);
                }
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
        return LuaValue.NIL;
    }

    public LuaValue save(String name,LuaString bs){
        if(mDocumentFile==null){
            select(new LuaFunction() {
                public LuaValue call(LuaValue arg1, LuaValue arg2) {
                    save(name,bs);
                    return LuaValue.NONE;
                }
            });
            return LuaValue.FALSE;
        }

        DocumentFile f = mDocumentFile.createFile("",name);
        try {
            if(f!=null) {
                OutputStream out = mActivity.getContentResolver().openOutputStream(f.getUri());
                if(out!=null) {
                    LuaUtil.save(out,bs);
                    return LuaValue.TRUE;
                }
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
        return LuaValue.FALSE;
    }



}
