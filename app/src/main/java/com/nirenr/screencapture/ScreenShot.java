package com.nirenr.screencapture;

import android.annotation.SuppressLint;
import android.annotation.TargetApi;
import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.graphics.Bitmap;
import android.graphics.PixelFormat;
import android.hardware.display.DisplayManager;
import android.hardware.display.VirtualDisplay;
import android.media.Image;
import android.media.ImageReader;
import android.media.projection.MediaProjection;
import android.media.projection.MediaProjectionManager;
import android.os.AsyncTask;
import android.os.Build;
import android.os.Handler;
import androidx.annotation.RequiresApi;
import android.util.DisplayMetrics;
import android.util.Log;
import android.view.WindowManager;
import android.widget.Toast;


import com.androlua.LuaAccessibilityService;
import com.androlua.LuaActivity;

import java.nio.ByteBuffer;

import static android.content.Context.MEDIA_PROJECTION_SERVICE;

import com.osfans.trime.BuildConfig;


@TargetApi(Build.VERSION_CODES.LOLLIPOP)
public class ScreenShot {


    private static LuaAccessibilityService sService;
    private static ScreenCaptureListener sScreenCaptureListener;
    private static Intent mResultData = null;

    public static void getResultData(final LuaAccessibilityService mService) {
        if (mService==null)
            return;
        if (mResultData == null) {
            Intent intent = new Intent(mService, ScreenCaptureActivity.class);
            intent.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            mService.startActivity(intent);
        }
    }


    public static void setResultData(Intent mResultData) {
        if (mResultData == null) {
            if (sService != null)
                Toast.makeText(sService, "未获得权限", Toast.LENGTH_SHORT).show();
            if (sScreenCaptureListener != null)
                sScreenCaptureListener.onScreenCaptureError("未获得权限");
            return;
        }

        ScreenShot.mResultData = mResultData;
        if (sService != null) {
            new Handler(sService.getMainLooper()).postDelayed(new Runnable() {
                @Override
                public void run() {
                    getScreenCaptureBitmap(sService, sScreenCaptureListener);
                }
            }, 500);
        }
        if (sContext != null) {
            new Handler(sContext.getMainLooper()).postDelayed(new Runnable() {
                @Override
                public void run() {
                    getScreenshot(sContext, sScreenshotCallback);
                }
            }, 500);
        }
    }

    public static void getScreenCaptureBitmap(final LuaAccessibilityService mService, final ScreenCaptureListener screenCaptureListener) {
        if(mService==null)
            return;
        
        ImageReader mImageReader = null;
        MediaProjection mMediaProjection = null;
        VirtualDisplay mVirtualDisplay = null;
        Image mImage;
        sService = mService;
        sScreenCaptureListener = screenCaptureListener;
        try {
            if (mResultData == null) {
                 Intent intent = new Intent(mService, ScreenCaptureActivity.class);
                intent.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                mService.startActivity(intent);
            } else {
                WindowManager mWindowManager = (WindowManager) mService.getSystemService(Context.WINDOW_SERVICE);
                DisplayMetrics metrics = new DisplayMetrics();
                int mScreenDensity;
                int mScreenWidth;
                int mScreenHeight;
                if (mWindowManager != null) {
                    mWindowManager.getDefaultDisplay().getRealMetrics(metrics);
                    mScreenDensity = metrics.densityDpi;
                    mScreenWidth = metrics.widthPixels;
                    mScreenHeight = metrics.heightPixels;
                }else{
                    mScreenHeight = mService.getHeight();
                    mScreenWidth = mService.getWidth();
                    mScreenDensity = mService.getDensity();
                }
                mImageReader = ImageReader.newInstance(mScreenWidth, mScreenHeight, PixelFormat.RGBA_8888, 1);
                
                mMediaProjection = ((MediaProjectionManager) mService.getSystemService(Context.MEDIA_PROJECTION_SERVICE)).getMediaProjection(Activity.RESULT_OK, mResultData);
                
                mVirtualDisplay = mMediaProjection.createVirtualDisplay("screen-mirror",
                        mScreenWidth, mScreenHeight, mScreenDensity, DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                        mImageReader.getSurface(), null, null);
                

                mImage = mImageReader.acquireLatestImage();
                for (int i = 0; i < 40; i++) {
                    try {
                        Thread.sleep(5);
                    } catch (InterruptedException e) {
                        e.printStackTrace();
                    }
                    mImage = mImageReader.acquireLatestImage();
                    
                    if (mImage != null)
                        break;
                }

                if (mImage == null) {
                    screenCaptureListener.onScreenCaptureError("请重试");
                } else {
                    int width = mImage.getWidth();
                    int height = mImage.getHeight();
                    final Image.Plane[] planes = mImage.getPlanes();
                    final ByteBuffer buffer = planes[0].getBuffer();
                    //每个像素的间距
                    int pixelStride = planes[0].getPixelStride();
                    //总的间距
                    int rowStride = planes[0].getRowStride();
                    int rowPadding = rowStride - pixelStride * width;
                    Bitmap bitmap = Bitmap.createBitmap(width + rowPadding / pixelStride, height, Bitmap.Config.ARGB_4444);
                    bitmap.copyPixelsFromBuffer(buffer);
                    bitmap = Bitmap.createBitmap(bitmap, 0, 0, width, height);
                    mImage.close();
                    screenCaptureListener.onScreenCaptureDone(bitmap);
                }
                sService = null;
                sScreenCaptureListener = null;
            }
        } catch (Exception e) {
            e.printStackTrace();
            sScreenCaptureListener.onScreenCaptureError("请重试");
            sService = null;
            sScreenCaptureListener = null;
        } finally {
            if (mVirtualDisplay != null)
                mVirtualDisplay.release();
            if (mImageReader != null) {
                mImageReader.close();
            }
            if (mMediaProjection != null) {
                mMediaProjection.stop();
            }
        }
    }

    private final Context mService;
    public static Bitmap mScreenCaptureBitmap;
    public static String appName = "";
    private final VirtualDisplay.Callback mCallback;
    private ScreenCaptureListener mScreenCaptureListener;
    private Image mImage;
    private static ScreenShot mScreenShot;
    private MediaProjection mMediaProjection;
    private VirtualDisplay mVirtualDisplay;

    private ImageReader mImageReader;

    private int mScreenWidth;
    private int mScreenHeight;
    private int mScreenDensity;


    public ScreenShot(Context service,VirtualDisplay.Callback callback) {
        mService = service;
        mCallback=callback;
        init();
        if (mResultData == null) {
            Intent intent = new Intent(mService, ScreenCaptureActivity.class);
            intent.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            mService.startActivity(intent);
        }else{
            startVirtual();
        }
        //createImageReader();
    }

    private void init() {
        WindowManager mWindowManager = (WindowManager) mService.getSystemService(Context.WINDOW_SERVICE);
        DisplayMetrics metrics = new DisplayMetrics();
        mWindowManager.getDefaultDisplay().getRealMetrics(metrics);
        mScreenDensity = metrics.densityDpi;
        mScreenWidth = metrics.widthPixels;
        mScreenHeight = metrics.heightPixels;
        createImageReader();
    }


    public void startScreenShot(ScreenCaptureListener listener) {
        if (mScreenCaptureListener != null)
            return;
        mScreenCaptureListener = listener;
        startScreenShot();
    }

    public void startScreenShot() {

        Handler handler1 = new Handler();
        handler1.postDelayed(new Runnable() {
            public void run() {
                //start virtual
                startVirtual();
            }
        }, 5);

        handler1.postDelayed(new Runnable() {
            public void run() {
                //capture the screen
                startCapture();

            }
        }, 100);
    }

    public Bitmap getScreenShot() {
        return getCapture();
    }

    private void createImageReader() {
        mImageReader = ImageReader.newInstance(mScreenWidth, mScreenHeight, PixelFormat.RGBA_8888, 1);
    }

    public void reSize() {
        stopVirtual();
        closeImageReader();
        init();
        startVirtual();
    }

    public void startVirtual() {
        if (mMediaProjection != null) {
            virtualDisplay();
        } else {
            setUpMediaProjection();
            virtualDisplay();
        }
    }

    public void setUpMediaProjection() {
        if (mMediaProjection != null)
            return;
        if (mResultData == null) {
            Intent intent = new Intent(mService, ScreenCaptureActivity.class);
            intent.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            mService.startActivity(intent);
        } else {
            mMediaProjection = getMediaProjectionManager().getMediaProjection(Activity.RESULT_OK, mResultData);
        }
    }

    private MediaProjectionManager getMediaProjectionManager() {
        return (MediaProjectionManager) mService.getSystemService(MEDIA_PROJECTION_SERVICE);
    }

    private void virtualDisplay() {
        if (mMediaProjection == null)
            setUpMediaProjection();
        if (mMediaProjection == null)
            return;
        if (mVirtualDisplay != null)
            return;
        try {
            //init();
            mVirtualDisplay = mMediaProjection.createVirtualDisplay("screen-mirror",
                    mScreenWidth, mScreenHeight, mScreenDensity, DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                    mImageReader.getSurface(), mCallback, null);
        } catch (Exception e) {
            e.printStackTrace();
        }
    }

    private void startCapture() {
        if (mImage != null)
            return;
        mImage = mImageReader.acquireLatestImage();

        if (mImage == null) {
            if (mScreenCaptureListener != null) {
                mScreenCaptureListener.onScreenCaptureDone(null);
                mScreenCaptureListener = null;
            }
        } else {
            SaveTask mSaveTask = new SaveTask();
            mSaveTask.execute(mImage);
            //AsyncTaskCompat.executeParallel(mSaveTask, image);
        }
    }

    private Bitmap getCapture() {
        if(mImageReader==null)
            return null;
        mImage = mImageReader.acquireLatestImage();

        if (mImage == null) {
            return null;
        } else {
            int width = mImage.getWidth();
            int height = mImage.getHeight();
            final Image.Plane[] planes = mImage.getPlanes();
            final ByteBuffer buffer = planes[0].getBuffer();
            //每个像素的间距
            int pixelStride = planes[0].getPixelStride();
            //总的间距
            int rowStride = planes[0].getRowStride();
            int rowPadding = rowStride - pixelStride * width;
            Bitmap bitmap = Bitmap.createBitmap(width + rowPadding / pixelStride, height, Bitmap.Config.ARGB_8888);
            bitmap.copyPixelsFromBuffer(buffer);
            bitmap = Bitmap.createBitmap(bitmap, 0, 0, width, height);
            mImage.close();
            mImage = null;
            return bitmap;
        }
    }


    public void setScreenCaptureBitmap(Bitmap bitmap) {
        mScreenCaptureBitmap = bitmap;
    }


    public class SaveTask extends AsyncTask<Image, Void, Bitmap> {

        @Override
        protected Bitmap doInBackground(Image... params) {

            if (params == null || params.length < 1 || params[0] == null) {

                return null;
            }

            Image image = params[0];

            int width = image.getWidth();
            int height = image.getHeight();
            final Image.Plane[] planes = image.getPlanes();
            final ByteBuffer buffer = planes[0].getBuffer();
            //每个像素的间距
            int pixelStride = planes[0].getPixelStride();
            //总的间距
            int rowStride = planes[0].getRowStride();
            int rowPadding = rowStride - pixelStride * width;
            Bitmap bitmap = Bitmap.createBitmap(width + rowPadding / pixelStride, height, Bitmap.Config.ARGB_8888);
            bitmap.copyPixelsFromBuffer(buffer);
            bitmap = Bitmap.createBitmap(bitmap, 0, 0, width, height);
            image.close();
            mImage = null;
            if (mScreenCaptureListener != null) {
                mScreenCaptureListener.onScreenCaptureDone(bitmap);
                mScreenCaptureListener = null;
                return null;
            }

            return null;
        }

        @Override
        protected void onPostExecute(Bitmap bitmap) {
            super.onPostExecute(bitmap);
            //预览图片
            if (bitmap != null) {
                setScreenCaptureBitmap(bitmap);
                Log.e("ryze", "获取图片成功");
                //mService.startActivity(PreviewPictureActivity.newIntent(mService));
            }
        }
    }


    private void tearDownMediaProjection() {
        if (mMediaProjection != null) {
            mMediaProjection.stop();
            mMediaProjection = null;
        }
    }

    private void stopVirtual() {
        if (mVirtualDisplay == null) {
            return;
        }
        mVirtualDisplay.release();
        mVirtualDisplay = null;
    }

    private void closeImageReader() {
        if (mImageReader != null)
            mImageReader.close();
        mImageReader = null;
    }


    public void release() {
        stopVirtual();
        tearDownMediaProjection();
        closeImageReader();
        mScreenShot=null;
    }

    private static ScreenshotCallback sScreenshotCallback;
     private static LuaActivity sContext;

    @RequiresApi(api = Build.VERSION_CODES.LOLLIPOP)
    public static void getScreenshot(LuaActivity context, ScreenshotCallback callback) {
        if (context == null)
            return;

        if (BuildConfig.DEBUG) Log.w("Screenshot", "getScreenshot: " + mResultData);
        if (mResultData == null) {
            sScreenshotCallback = callback;
            sContext = context;
            getResultData(context);
            return;
        }
        sScreenshotCallback = null;
        sContext = null;
        getScreenshot(context, ((MediaProjectionManager) context.getSystemService(Context.MEDIA_PROJECTION_SERVICE)).getMediaProjection(Activity.RESULT_OK, mResultData), callback);
    }


    @RequiresApi(api = Build.VERSION_CODES.LOLLIPOP)
    private static void getScreenshot(final LuaActivity context, final MediaProjection mediaProjection, final ScreenshotCallback callback) {
        if (BuildConfig.DEBUG) Log.w("Screenshot", "getScreenshot: " + mediaProjection);
        int width_s = context.getWidth();//自己实现获取
        int height_s = context.getHeight();//自己实现获取
        int densityDpi = context.getDensity();//自己实现获取
        @SuppressLint("WrongConstant") final ImageReader mImageReader = ImageReader.newInstance(width_s, height_s, PixelFormat.RGBA_8888, 2);
        final VirtualDisplay virtualDisplay1 = mediaProjection.createVirtualDisplay("screen-mirror", width_s, height_s, densityDpi,
                DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR, mImageReader.getSurface(), null, null);
        mImageReader.setOnImageAvailableListener(new ImageReader.OnImageAvailableListener() {
            @Override
            public void onImageAvailable(ImageReader reader) {
                Image image = reader.acquireLatestImage();
                if (image != null) {
                    final Image.Plane[] planes = image.getPlanes();
                    final ByteBuffer buffer = planes[0].getBuffer();
                    int width = image.getWidth();
                    int height = image.getHeight();
                    if (BuildConfig.DEBUG) Log.w("Screenshot", "onImageAvailable:1 " + width);
                    if (height < 1) {
                        image.close();
                        return;
                    }
                    int pixelStride = planes[0].getPixelStride();
                    int rowStride = planes[0].getRowStride();
                    int rowPadding = rowStride - pixelStride * width;
                    int bmpWidth = width + rowPadding / pixelStride;
                    int bmpHeight = height;
                    if (BuildConfig.DEBUG) Log.w("Screenshot", "onImageAvailable:2 " + bmpWidth);
                    Bitmap bitmap = Bitmap.createBitmap(bmpWidth, bmpHeight, Bitmap.Config.ARGB_8888);
                    bitmap.copyPixelsFromBuffer(buffer);
                    callback.onSuccess(bitmap);
                    bitmap.recycle();
                    image.close();
                    virtualDisplay1.release();
                    mediaProjection.stop();
                }
                reader.close();
            }
        }, null);
    }

    public static void getResultData(final LuaActivity activity) {
        if (activity == null)
            return;
        if (mResultData == null) {
            try {
                Intent intent = new Intent(activity, ScreenCaptureActivity.class);
                intent.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TASK | Intent.FLAG_ACTIVITY_NO_HISTORY);
                if (BuildConfig.DEBUG)
                    Log.w("Screenshot", "getResultData:ScreenCaptureActivity intent " + intent);
                activity.startActivity(intent);
            } catch (Exception e) {
                if (BuildConfig.DEBUG)
                    e.printStackTrace();
                else if (BuildConfig.DEBUG) Log.w("Screenshot", "getResultData: " + e.toString());
            }
        }
    }



    public interface ScreenshotCallback {
        public void onSuccess(Bitmap bitmap);

        public void onFailure(String err);
    }



}
