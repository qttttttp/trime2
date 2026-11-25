/*******************************************************************************
 * Copyright (c) 2009-2011 Luaj.org. All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 ******************************************************************************/
package com.myopicmobile.textwarrior.common;

import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.Reader;
import java.util.Hashtable;

import org.luaj.Globals;
import org.luaj.LuaClosure;
import org.luaj.LuaString;
import org.luaj.LuaValue;
import org.luaj.Prototype;
import org.luaj.lib.BaseLib;

/**
 * Compiler for Lua.
 *
 * <p>
 * Compiles lua source files into lua bytecode within a {@link Prototype},
 * loads lua binary files directly into a {@link Prototype},
 * and optionaly instantiates a {@link LuaClosure} around the result
 * using a user-supplied environment.
 *
 * <p>
 * Implements the {@link org.luaj.Globals.Compiler} interface for loading
 * initialized chunks, which is an interface common to
 * lua bytecode compiling and java bytecode compiling.
 *
 * <p>
 * The {@link LuaC} compiler is installed by default by both the
 * <p>
 * so in the following example, the default {@link LuaC} compiler
 * will be used:
 * <pre> {@code
 * Globals globals = JsePlatform.standardGlobals();
 * globals.load(new StringReader("print 'hello'"), "main.lua" ).call();
 * } </pre>
 * <p>
 * To load the LuaC compiler manually, use the install method:
 * <pre> {@code
 * LuaC.install(globals);
 * } </pre>
 *
 * @see Globals#compiler
 * @see Globals#loader
 * @see org.luaj.lib.jse.JsePlatform
 * @see BaseLib
 * @see LuaValue
 * @see Prototype
 */
public class LuaC extends Constants {

    /**
     * A sharable instance of the LuaC compiler.
     */
    public static final LuaC instance = new LuaC();


    public static Prototype lexer(CharSequence stream, String chunkname, Globals globals, Flag _abort) throws IOException {
        return (new CompileState()).luaY_parser2(new UTF8Stream(new StrReader(stream.toString())), chunkname, globals, _abort);
    }

    protected LuaC() {
    }

    static class CompileState {
        int nCcalls = 0;
        private Hashtable strings = new Hashtable();

        protected CompileState() {
        }

        private Prototype luaY_parser2(InputStream z, String name, Globals globals, Flag _abort) throws IOException {
            LexState lexstate = new LexState(this, z, true, _abort);
            FuncState funcstate = new FuncState();
            // lexstate.buff = buff;
            lexstate.globals = globals;
            lexstate.fs = funcstate;
            lexstate.setinput(this, z.read(), z, (LuaString) LuaValue.valueOf(name));
            /* main func. is always vararg */
            funcstate.f = new Prototype();
            funcstate.f.source = (LuaString) LuaValue.valueOf(name);
            lexstate.mainfunc(funcstate);
            LuaC._assert(funcstate.prev == null,"");
            /* all scopes should be correctly finished */
            LuaC._assert(lexstate.dyd == null
                    || (lexstate.dyd.n_actvar == 0 && lexstate.dyd.n_gt == 0 && lexstate.dyd.n_label == 0),"");
            return funcstate.f;
        }

        // look up and keep at most one copy of each string
        public LuaString newTString(String s) {
            return cachedLuaString(LuaString.valueOf(s));
        }

        // look up and keep at most one copy of each string
        public LuaString newTString(LuaString s) {
            return cachedLuaString(s);
        }

        public LuaString cachedLuaString(LuaString s) {
            LuaString c = (LuaString) strings.get(s);
            if (c != null)
                return c;
            strings.put(s, s);
            return s;
        }

        public String pushfstring(String string) {
            return string;
        }
    }

    abstract static class AbstractBufferedStream extends InputStream {
        protected byte[] b;
        protected int i = 0, j = 0;
        protected AbstractBufferedStream(int buflen) {
            this.b = new byte[buflen];
        }
        abstract protected int avail() throws IOException;
        public int read() throws IOException {
            int a = avail();
            return (a <= 0 ? -1 : 0xff & b[i++]);
        }
        public int read(byte[] b) throws IOException {
            return read(b, 0, b.length);
        }
        public int read(byte[] b, int i0, int n) throws IOException {
            int a = avail();
            if (a <= 0) return -1;
            final int n_read = Math.min(a, n);
            System.arraycopy(this.b,  i,  b,  i0,  n_read);
            i += n_read;
            return n_read;
        }
        public long skip(long n) throws IOException {
            final long k = Math.min(n, j - i);
            i += k;
            return k;
        }
        public int available() throws IOException {
            return j - i;
        }
    }

    /**  Simple converter from Reader to InputStream using UTF8 encoding that will work
     * on both JME and JSE.
     * This class may be moved to its own package in the future.
     */
    static class UTF8Stream extends AbstractBufferedStream {
        private final char[] c = new char[32];
        private final Reader r;
        UTF8Stream(Reader r) {
            super(96);
            this.r = r;
        }
        protected int avail() throws IOException {
            if (i < j) return j - i;
            int n = r.read(c);
            if (n < 0)
                return -1;
            if (n == 0) {
                int u = r.read();
                if (u < 0)
                    return -1;
                c[0] = (char) u;
                n = 1;
            }
            j = LuaString.encodeToUtf8(c, n, b, i = 0);
            return j;
        }
        public void close() throws IOException {
            r.close();
        }
    }

    static class StrReader extends Reader {
        final String s;
        int i = 0;
        final int n;
        StrReader(String s) {
            this.s = s;
            n = s.length();
        }
        public void close() throws IOException {
            i = n;
        }
        public int read() throws IOException {
            return i < n ? s.charAt(i++) : -1;
        }
        public int read(char[] cbuf, int off, int len) throws IOException {
            int j = 0;
            for (; j < len && i < n; ++j, ++i)
                cbuf[off+j] = s.charAt(i);
            return j > 0 || len == 0 ? j : -1;
        }
    }

}
