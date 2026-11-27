package com.androlua;

import android.content.Intent;
import android.os.Bundle;

import java.io.File;

public class Main extends LuaActivity {

    @Override
    public void onCreate(Bundle savedInstanceState) {
        // TODO: Implement this method
        super.onCreate(savedInstanceState);
        /*if (savedInstanceState == null && getIntent().getData() != null)
            onNewIntent(getIntent());
        if (getIntent().getBooleanExtra("isVersionChanged", false) && (savedInstanceState == null)) {
            onVersionChanged(getIntent().getStringExtra("newVersionName"), getIntent().getStringExtra("oldVersionName"));
        }*/
    }

    @Override
    protected void onNewIntent(Intent intent) {
        // TODO: Implement this method
        runFunc("onNewIntent", intent);
        super.onNewIntent(intent);
    }

    private void onVersionChanged(String newVersionName, String oldVersionName) {
        // TODO: Implement this method
        runFunc("onVersionChanged", newVersionName, oldVersionName);

    }


}
