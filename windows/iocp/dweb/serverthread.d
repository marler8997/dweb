module dweb.serverthread;

//import std.array : Appender, appender;

import more.net :
    lastError, htons, isInvalid, failed, socklen_t,
    in_addr, inet_sockaddr, SocketType, Protocol, Shutdown,
    createsocket, closesocket, bind, listen, accept, shutdown, recv
    ;

import dweb.types;
import dweb.util;
import dweb.log;

template Platform(Hooks)
{
    struct Server
    {
        passfail init()
        {
            return passfail.pass;
        }

        int serverLoop()
        {
            errorf("windows serverLoop not implemented");
            return 1;
            /*
            for(;;)
            {
                // TODO: how many events? There is a MAXEVENTS, maybe I should use that?
                epoll_event[100] events;
                auto eventCount = epoll_wait(epollHandle, events.ptr, events.length, -1);
                if(eventCount == -1)
                {
                    errorf("epoll_wait function failed (e=%s)", lastError);
                    return 1; // fail
                }
                logf("got %s epoll event(s)", eventCount);
                foreach(i; 0 .. eventCount)
                {
                    auto handlerID = events[i].data.u64;
                    auto result = epollHandlers.appender.data[handlerID].callback(IndexID!EpollHandler(handlerID),
                        epollHandlers.appender.data[handlerID].fd, events[i].events);
                    if(result != 0)
                    {
                        errorf("epoll callback returned error %s", result);
                        return 1; // fail
                    }
                }
            }

            return 0;
            */
        }
    }

/+
    static if(Hooks.GlobalServerInstance)
    {
        __gshared Server globalServer;
        int globalListenCallback(IndexID!EpollHandler epollHandlerID, int fd, uint events)
        {
            logf("listenCallback(s=%s) events=0x%x", fd, events);
            /*
            if(events & EPOLLIN)
            {
                events = events & ~EPOLLIN;

                inet_sockaddr from;
                socklen_t fromlen = from.sizeof;

                auto newClient = accept(fd, &from);
                if(newClient.isInvalid)
                {
                    errorf("accept(s=%s) failed (e=%s)", fd, lastError);
                    return 1; // fail
                }
                logf("received new connection from %s", from);

                if(addEpollHandler(newClient, EPOLLIN, &dataCallback).failed)
                {
                    // error already logged
                    shutdown(newClient, Shutdown.both);
                    closesocket(newClient);
                }
            }

            if(events)
            {
                errorf("listenCallback(s=%s) unknown event(s) 0x%x", events);
                return 1; // fail
            }
            return 0; // success
            */
            return 1; // fail
        }
        int globalDataCallback(IndexID!EpollHandler epollHandlerID, int fd, uint events)
        {
            logf("dataCallback(s=%s) events=0x%x", fd, events);
            /*
            if(events & EPOLLIN)
            {
                events = events & ~EPOLLIN;

                ubyte[100] buffer;
                auto length = recv(fd, buffer);
                if(length <= 0)
                {
                    logf("dataCallback(s=%s) recv returned %s (e=%s)", fd, length, lastError);
                    shutdown(fd, Shutdown.both);
                    closesocket(fd);
                    freeEpollHandler(epollHandlerID);
                    return 0;
                }
                logf("dataCallback(s=%s) read %s bytes of data", fd, length);
            }
            if(events)
            {
                errorf("dataCallback(s=%s) unknown event(s) 0x%x", fd, events);
                return 1; // fail
            }
            return 0;
            */
            return 1; // fail
        }
    }
    +/
}