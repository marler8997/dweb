module dweb.util;

import std.array : Appender, appender;

struct IndexID(T)
{
    size_t index;
}

// Requires: T.nullValue and T.isNull
struct CompactList(T)
{
    static assert(T.nullValue.isNull);

    Appender!(T[]) appender;
    size_t usedLength;
    // Note: make sure to initialize the value afterwards
    //       otherwise it can be overriden by another call to an add function.
    IndexID!T addNoInit()
    {
        size_t i = 0;
        for(; i < appender.data.length; i++)
        {
            if(appender.data[i].isNull)
            {
                goto ADDED;
            }
        }
        appender.put(T.nullValue);
      ADDED:
        usedLength++;
        return IndexID!T(i);
    }
    IndexID!T add(T value) in { assert(!value.isNull); } body
    {
        size_t i = 0;
        for(; i < appender.data.length; i++)
        {
            if(appender.data[i].isNull)
            {
                appender.data[i] = value;
                goto ADDED;
            }
        }
        appender.put(value);
      ADDED:
        usedLength++;
        return IndexID!T(i);
    }
    void free(IndexID!T id)
    {
        appender.data[id.index] = T.nullValue;
        usedLength--;
    }
}

struct Partial
{
    Appender!(char[]) appender;
    void reset()
    {
        appender.clear();
    }
    void append(const(char)[] buffer)
    {
        appender.put(buffer);
        //logf("append %s bytes \"%s\", total is %s bytes \"%s\"",
        //    buffer.length, buffer, appender.data.length, appender.data);
    }
    auto finish(const(char)[] buffer)
    {
        if(appender.data.length == 0)
        {
            return buffer;
        }
        appender.put(buffer);
        auto final_ = appender.data;
        reset();
        return final_;
    }
}