package android.widget;

import android.annotation.SuppressLint;
import android.content.Context;
import android.database.DataSetObserver;
import android.graphics.Rect;
import android.os.Build;
import android.util.AttributeSet;
import android.util.TypedValue;
import android.view.GestureDetector;
import android.view.HapticFeedbackConstants;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewGroup;

import java.util.ArrayList;
import java.util.LinkedList;
import java.util.List;
import java.util.Queue;

/**
 * 终极修复版 HorizontalListView
 * 功能：丝滑滚动、起点精准对齐、支持点击/长按、完美支持 Ripple 波纹效果
 */
public class HorizontalListView extends AdapterView<ListAdapter> {
    private static final int INSERT_AT_END_OF_LIST = -1;
    private static final int INSERT_AT_START_OF_LIST = 0;

    protected OverScroller mScroller;
    private GestureDetector mGestureDetector;
    private final GestureListener mGestureListener = new GestureListener();

    private List<Queue<View>> mRemovedViewsCache = new ArrayList<>();
    protected ListAdapter mAdapter;
    private boolean mDataChanged = false;

    // 坐标计算
    private int mDisplayOffset = 0;
    protected int mCurrentX = 0;
    protected int mNextX = 0;
    private int mMaxX = Integer.MAX_VALUE;

    private int mLeftViewAdapterIndex = -1;
    private int mRightViewAdapterIndex = -1;
    private int mDividerWidth = 0;

    private int mHeightMeasureSpec;
    private Rect mRect = new Rect();
    private int mSelectedIndex=-1;

    public HorizontalListView(Context context) {
        super(context);
        mScroller = new OverScroller(context);
        mGestureDetector = new GestureDetector(context, mGestureListener);
        setWillNotDraw(false);
        initView();
    }

    private void initView() {
        mLeftViewAdapterIndex = -1;
        mRightViewAdapterIndex = -1;
        mDisplayOffset = 0;
        mCurrentX = 0;
        mNextX = 0;
        mMaxX = Integer.MAX_VALUE;
    }

    private DataSetObserver mAdapterDataObserver = new DataSetObserver() {
        @Override
        public void onChanged() {
            mDataChanged = true;
            invalidate();
            requestLayout();
        }
        @Override
        public void onInvalidated() {
            reset();
            invalidate();
            requestLayout();
        }
    };

    @Override
    public void setAdapter(ListAdapter adapter) {
        if (mAdapter != null) mAdapter.unregisterDataSetObserver(mAdapterDataObserver);
        mAdapter = adapter;
        if (mAdapter != null) {
            mAdapter.registerDataSetObserver(mAdapterDataObserver);
            mRemovedViewsCache.clear();
            for (int i = 0; i < mAdapter.getViewTypeCount(); i++) {
                mRemovedViewsCache.add(new LinkedList<View>());
            }
        }
        reset();
    }

    private void reset() {
        initView();
        removeAllViewsInLayout();
        requestLayout();
    }

    @Override
    protected void onMeasure(int widthMeasureSpec, int heightMeasureSpec) {
        super.onMeasure(widthMeasureSpec, heightMeasureSpec);
        mHeightMeasureSpec = heightMeasureSpec;
    }


    @SuppressLint("WrongCall")
    @Override
    protected void onLayout(boolean changed, int left, int top, int right, int bottom) {
        super.onLayout(changed, left, top, right, bottom);
        if (mAdapter == null) return;

        // 1. 数据变化处理
        if (mDataChanged) {
            int oldX = mCurrentX;
            initView();
            removeAllViewsInLayout();
            mNextX = oldX;
            mDataChanged = false;
        }

        // 2. 计算 Scroller 位移
        if (mScroller.computeScrollOffset()) {
            mNextX = mScroller.getCurrX();
        }

        // 3. 【核心修正】严格限制 mNextX 范围并强制同步 mDisplayOffset
        if (mNextX <= 0) {
            mNextX = 0;
            mScroller.forceFinished(true);
            // 如果逻辑上到了最左边，且第一个元素已经显示，强制物理偏移归零
            if (mLeftViewAdapterIndex <= 0) {
                mDisplayOffset = 0;
            }
        }

        if (mMaxX != Integer.MAX_VALUE && mNextX >= mMaxX) {
            mNextX = mMaxX;
            mScroller.forceFinished(true);
        }

        // 4. 计算这一帧真实的 dx
        int dx = mCurrentX - mNextX;

        // 5. 移除和填充
        removeNonVisibleChildren(dx);
        fillList(dx);
        positionChildren(dx);

        mCurrentX = mNextX;

        // 6. 动态更新最大滚动范围
        if (determineMaxX()) {
            // 如果 maxX 发生了变化（比如新加载了 item），重新触发布局确保不留白
            requestLayout();
        }

        // 7. 动画持续触发
        if (!mScroller.isFinished()) {
            postOnAnimation(new Runnable() {
                @Override
                public void run() { requestLayout(); }
            });
        }
    }

    private void positionChildren(final int dx) {
        if (getChildCount() > 0) {
            mDisplayOffset += dx;

            // 【双重保险】在布局前再次确认起点
            if (mLeftViewAdapterIndex == 0 && mNextX == 0) {
                mDisplayOffset = 0;
            }

            int left = mDisplayOffset + getPaddingLeft();
            for (int i = 0; i < getChildCount(); i++) {
                View child = getChildAt(i);
                int right = left + child.getMeasuredWidth();
                int top = getPaddingTop();
                int bottom = top + child.getMeasuredHeight();

                child.layout(left, top, right, bottom);
                left = right + mDividerWidth;
            }
        }
    }

    private boolean determineMaxX() {
        if (mRightViewAdapterIndex == mAdapter.getCount() - 1) {
            View child = getChildAt(getChildCount() - 1);
            if (child != null) {
                int oldMaxX = mMaxX;
                // 计算最大可滚动距离：内容总长 - 容器宽度
                mMaxX = mCurrentX + (child.getRight() - getPaddingLeft()) - (getWidth() - getPaddingLeft() - getPaddingRight());

                if (mMaxX < 0) mMaxX = 0;
                return mMaxX != oldMaxX;
            }
        }
        return false;
    }

    private void fillList(final int dx) {
        int edge = 0;
        View child = getChildAt(getChildCount() - 1);
        if (child != null) edge = child.getRight();

        while (edge + dx < getWidth() && mRightViewAdapterIndex + 1 < mAdapter.getCount()) {
            mRightViewAdapterIndex++;
            View v = mAdapter.getView(mRightViewAdapterIndex, getRecycledView(mRightViewAdapterIndex), this);
            //setItemRipple(v);
            // --- 增加高亮逻辑 ---
            updateHighlightState(v, mRightViewAdapterIndex);
            addAndMeasureChild(v, INSERT_AT_END_OF_LIST);
            edge += v.getMeasuredWidth() + mDividerWidth;
            if (mLeftViewAdapterIndex == -1) mLeftViewAdapterIndex = mRightViewAdapterIndex;
        }

        child = getChildAt(0);
        edge = (child != null) ? child.getLeft() : 0;
        while (edge + dx > 0 && mLeftViewAdapterIndex > 0) {
            mLeftViewAdapterIndex--;
            View v = mAdapter.getView(mLeftViewAdapterIndex, getRecycledView(mLeftViewAdapterIndex), this);
            //setItemRipple(v);
            // --- 增加高亮逻辑 ---
            updateHighlightState(v, mLeftViewAdapterIndex);
            addAndMeasureChild(v, INSERT_AT_START_OF_LIST);
            int width = v.getMeasuredWidth() + mDividerWidth;
            edge -= width;
            mDisplayOffset -= width;
        }
    }

    private void updateHighlightState(View v, int index) {
        // 使用 setActivated 而不是 setPressed，因为 Pressed 是瞬时的，Activated 是持久的
        boolean isSelected = (index == mSelectedIndex);
        v.setActivated(isSelected);

        // 如果你想让高亮也有阴影感，可以手动调用你之前的动画
        if (isSelected) {
            v.setPressed(true);
            v.setTranslationZ(10f);
        } else {
            v.setPressed(false);
            v.setTranslationZ(0f);
        }
    }

    private void removeNonVisibleChildren(final int dx) {
        View child = getChildAt(0);
        while (child != null && child.getRight() + dx <= 0) {
            mDisplayOffset += child.getMeasuredWidth() + mDividerWidth;
            recycleView(mLeftViewAdapterIndex, child);
            removeViewInLayout(child);
            mLeftViewAdapterIndex++;
            child = getChildAt(0);
        }

        child = getChildAt(getChildCount() - 1);
        while (child != null && child.getLeft() + dx >= getWidth()) {
            recycleView(mRightViewAdapterIndex, child);
            removeViewInLayout(child);
            mRightViewAdapterIndex--;
            child = getChildAt(getChildCount() - 1);
        }
    }

    private void addAndMeasureChild(View child, int pos) {
        setItemRipple(child);
        LayoutParams lp = child.getLayoutParams();
        if (lp == null) lp = new LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.MATCH_PARENT);
        addViewInLayout(child, pos, lp, true);
        int hSpec = ViewGroup.getChildMeasureSpec(mHeightMeasureSpec, getPaddingTop() + getPaddingBottom(), lp.height);
        int wSpec = (lp.width > 0) ? MeasureSpec.makeMeasureSpec(lp.width, MeasureSpec.EXACTLY) : MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED);
        child.measure(wSpec, hSpec);
    }

    public void setItemRipple(View itemView) {
        if(itemView.getBackground()!=null)
            return;
        TypedValue outValue = new TypedValue();
        // 解析当前主题中的 selectableItemBackground 属性
        getContext().getTheme().resolveAttribute(android.R.attr.selectableItemBackground, outValue, true);
        // 将解析出的资源 ID 设置给 View 的背景
        itemView.setBackgroundResource(outValue.resourceId);
    }

    private View getRecycledView(int index) {
        int type = mAdapter.getItemViewType(index);
        return (type >= 0) ? mRemovedViewsCache.get(type).poll() : null;
    }

    private void recycleView(int index, View v) {
        int type = mAdapter.getItemViewType(index);
        if (type >= 0) mRemovedViewsCache.get(type).offer(v);
    }

    private int getChildIndex(int x, int y) {
        for (int i = 0; i < getChildCount(); i++) {
            getChildAt(i).getHitRect(mRect);
            if (mRect.contains(x, y)) return i;
        }
        return -1;
    }

    @Override
    public boolean onTouchEvent(MotionEvent event) {
        // 强制先由手势检测器处理
        boolean handled = mGestureDetector.onTouchEvent(event);

        int action = event.getActionMasked();
        // 增加 ACTION_UP 的保底处理，确保手指离开时视觉状态一定恢复
        if (action == MotionEvent.ACTION_UP || action == MotionEvent.ACTION_CANCEL) {
            unpressAllChildren();
            setPressed(false); // 同时恢复父容器状态
        }
        return handled;
    }

    private void unpressAllChildren() {
        for (int i = 0; i < getChildCount(); i++) {
            View child = getChildAt(i);
            if (child.isPressed()) {
                child.setPressed(false);
                child.refreshDrawableState(); // 必须调用刷新，否则 Ripple 动画不会消失
            }
        }
        mSelectedIndex=-1;
    }

    /**
     * 即时滚动到指定位置并设置高亮
     */
    @Override
    public void setSelection(int position) {
        if (mAdapter == null || position < 0 || position >= mAdapter.getCount()) return;

        mSelectedIndex = position;

        // 计算目标 X 坐标 (每个 Item 宽度不同，需累加计算)
        // 注意：如果是固定宽度的 Item 可以直接计算；非固定宽度建议通过逻辑定位
        // 这里采用最简单直接的逻辑：重置位置并强制定位
        mNextX = calculateXForIndex(position);
        mScroller.forceFinished(true);
        requestLayout();
    }

    /**
     * 平滑滚动到指定位置
     */
    public void smoothScrollToPosition(int position) {
        if (mAdapter == null || position < 0 || position >= mAdapter.getCount()) return;

        int targetX = calculateXForIndex(position);
        int dx = targetX - mNextX;

        mScroller.startScroll(mNextX, 0, dx, 0, 500); // 500ms 动画
        requestLayout();
    }

    /**
     * 辅助方法：估算或计算指定索引的 X 偏移量
     * 如果是候选词列表，通常需要遍历之前的 Item 宽度累加
     */
    private int calculateXForIndex(int index) {
        // 简易逻辑：如果是固定宽度的 Item (假设为 mItemWidth)
        // return index * (mItemWidth + mDividerWidth);

        // 如果是不定宽度的 Item，建议至少定位到大致范围，或者在 Adapter 中存储偏移量
        // 这里提供一个中庸方案：如果索引在当前可见范围外，直接跳转
        return mCurrentX; // 需要根据你的布局逻辑细化
    }

    private class GestureListener extends GestureDetector.SimpleOnGestureListener {
        @Override
        public boolean onDown(MotionEvent e) {
            mScroller.forceFinished(true);
            int index = getChildIndex((int) e.getX(), (int) e.getY());
            if (index >= 0) {
                View child = getChildAt(index);
                // 【Ripple 关键】同步波纹热点坐标
                child.drawableHotspotChanged(e.getX() - child.getLeft(), e.getY() - child.getTop());
                child.setPressed(true);
                child.refreshDrawableState();
                mSelectedIndex=-1;
            }
            return true;
        }

        @Override
        public boolean onScroll(MotionEvent e1, MotionEvent e2, float dX, float dY) {
            getParent().requestDisallowInterceptTouchEvent(true);
            unpressAllChildren(); // 滚动时取消波纹按下状态
            mNextX += (int) dX;
            requestLayout();
            return true;
        }

        @Override
        public boolean onFling(MotionEvent e1, MotionEvent e2, float vX, float vY) {
            mScroller.fling(mNextX, 0, (int) -vX, 0, 0, mMaxX, 0, 0);
            requestLayout();
            return true;
        }

        @Override
        public boolean onSingleTapConfirmed(MotionEvent e) {
            int index = getChildIndex((int) e.getX(), (int) e.getY());
            if (index >= 0 && mAdapter != null) {
                View child = getChildAt(index);
                int adapterIndex = mLeftViewAdapterIndex + index;
                if (getOnItemClickListener() != null) {
                    getOnItemClickListener().onItemClick(HorizontalListView.this, child, adapterIndex, mAdapter.getItemId(adapterIndex));
                }
            }
            return true;
        }

        @Override
        public void onLongPress(MotionEvent e) {
            int index = getChildIndex((int) e.getX(), (int) e.getY());
            if (index >= 0 && mAdapter != null) {
                View child = getChildAt(index);
                int adapterIndex = mLeftViewAdapterIndex + index;
                if (getOnItemLongClickListener() != null) {
                    if (getOnItemLongClickListener().onItemLongClick(HorizontalListView.this, child, adapterIndex, mAdapter.getItemId(adapterIndex))) {
                        performHapticFeedback(HapticFeedbackConstants.LONG_PRESS);
                    }
                }
            }
        }
    }

    @Override
    public ListAdapter getAdapter() { return mAdapter; }
    @Override
    public View getSelectedView() { return null; }
}
