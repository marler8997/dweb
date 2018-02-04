module dweb.serverthread;

import core.stdc.string : memcpy;
//import std.array : Appender, appender;
import std.typecons : Flag, Yes, No;

import more.alloc : GCDoubler;
import more.types : passfail, passed, failed;
import more.net :
    lastError, htons, isInvalid, failed, socket_t, socklen_t,
    in_addr, inet_sockaddr, SocketType, Protocol, Shutdown,
    createsocket, closesocket, bind, listen, accept, shutdown, recv,
    select, fd_set_dynamic
    ;

import dweb.util;
import dweb.log;
import dweb.server : HandlerResult;

/*
Terminology:
Callback: A function/function pointer to code that handles events.
Handler: The file descriptor/callback/data that handles events.
*/

enum SelectEventFlag : ubyte
{
    read  = 0x01,
    write = 0x02,
    error = 0x04,
}
/*
enum SelectEventID : ubyte
{
    read = 0,
    write = 1,
    error = 2,
}
*/

template ServerThread(Hooks)
{
    private alias GenericData = ubyte[Hooks.ExtraHandlerDataSize];

    struct Event(T)
    {
        static if(!Hooks.isGlobal)
        {
            ServerThreadStruct* serverThread;
        }
        HandlerData!T* data;
        alias data this;
    }

    // WORKAROUND: for some reason, these need to be defined inside the same
    //             'static if' as the ServerThreadStruct.  So I've defined
    //             them as a string and I mix in the same declarations in both cases.
    private enum CommonMixinCode = q{
        private alias GenericEvent = Event!GenericData;
        alias Callback(T) = HandlerResult function(Event!T event);
        private alias GenericCallback = Callback!GenericData;
    };
    static if(Hooks.isGlobal)
    {
        mixin(CommonMixinCode);
        mixin ServerMembers;
    }
    else
    {
        mixin(CommonMixinCode);
        struct ServerThreadStruct
        {
            mixin ServerMembers;
        }
    }
    struct HandlerData(T)
    {
        @property static HandlerData nullValue() { return HandlerData(); }
        @property auto isNull() const { return callback is null; }
        Callback!T callback;
        socket_t sock;
        private SelectEventFlag selectEvents;
        T extra = void;
        alias extra this;
    }
    alias GenericHandlerData = HandlerData!GenericData;
}
mixin template ServerMembers()
{
    import more.alloc : GCDoubler;
    import more.builder : Builder;
    Builder!(GenericHandlerData, GCDoubler!64) handlers;
    passfail init()
    {
        return passfail.pass;
    }

/*
    private auto freeEpollHandler(IndexID!GenericHandlerData id)
    {
        epollHandlers.free(id);
    }
    */
    private passfail addHandler(socket_t sock, GenericCallback callback, SelectEventFlag selectEvents,
        void* data, size_t dataOffset, size_t dataLength)
    {
        auto newHandler = handlers.reserveOne(Yes.initialize);
        if(data && dataLength)
        {
            memcpy(cast(ubyte*)newHandler + dataOffset, data, dataLength);
        }
        newHandler.callback = callback;
        newHandler.sock = sock;
        newHandler.selectEvents = selectEvents;
        return passfail.pass;
    }

    passfail addReadSocket(T)(socket_t sock, Callback!T callback, T* handlerData)
    {
        static if(HandlerData!T.sizeof > GenericHandlerData.sizeof)
        {
            import std.conv : to;
            static assert(0,
                "HandlerData!(" ~ T.stringof ~ ") of size " ~ HandlerData!T.sizeof.to!string  ~ " is too large for this thread which has a max of " ~ 
                GenericHandlerData.sizeof.to!string ~ ". Increase the ExtraHandlerDataSize to make room.");
        }
        return addHandler(sock, cast(GenericCallback)callback, SelectEventFlag.read,
            handlerData, HandlerData!T.extra.offsetof, T.sizeof);
    }

/*
    pragma(inline)
    GenericEvent createCallbackArg(size_t handlerID)
    {
        static if(Hooks.isGlobal)
        {
            return GenericEvent(&epollHandlers.appender.data[handlerID]);
        }
        else
        {
            return GenericEvent(&this, &epollHandlers.appender.data[handlerID]);
        }
    }
    */

    int serverLoop()
    {
        fd_set_dynamic!(GCDoubler!64)[3] socketSets;

        for(;;)
        {
            socketSets[0].reset();
            socketSets[1].reset();
            socketSets[2].reset();

            foreach(ref handler; handlers.data)
            {
                if(handler.selectEvents & SelectEventFlag.read)
                {
                    socketSets[0].addNoCheck(handler.sock);
                }
            }

            int selectResult = select(0,
                socketSets[0].ptr,
                socketSets[1].ptr,
                socketSets[2].ptr,
                null);
            if(selectResult < 0)
            {
                errorf("select failed (e=%s)", lastError);
                return 1; // fail
            }


            logf("select result is %s (not implemented)", selectResult);
            return 1;
            /*
            select


            // TODO: how many events? There is a MAXEVENTS, maybe I should use that?
            epoll_event[100] events;
            auto eventCount = epoll_wait(epollHandle, events.ptr, events.length, -1);
            if(eventCount == -1)
            {
                errorf("epoll_wait function failed (e=%s)", lastError);
                return 1; // fail
            }
            //logf("got %s epoll event(s)", eventCount);
            foreach(i; 0 .. eventCount)
            {
                static if(size_t.sizeof == 8)
                {
                    auto handlerID = events[i].data.u64;
                }
                else
                {
                    auto handlerID = events[i].data.u32;
                }
                auto result = epollHandlers.appender.data[handlerID].callback(
                    createCallbackArg(handlerID));
                final switch(result)
                {
                    case HandlerResult.success:
                        break;
                    case HandlerResult.removeSocket:
                        freeEpollHandler(IndexID!GenericHandlerData(handlerID));
                        break;
                    case HandlerResult.errorStopServer:
                        errorf("epoll callback returned error %s", result);
                        return 1; // fail
                }
            }
            */
        }

        return 0;
    }
}

