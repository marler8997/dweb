import std.stdio;

import std.typecons : Flag, Yes, No;

import more.types;
import more.net : socket_t, isInvalid, htons, in_addr, inet_sockaddr;

import dweb.types;
import dweb.log;
import dweb.serverthread : ServerThread;
import dweb.server : HandlerResult;
import dweb.net : createListenSocket;
import dweb.httpserver : HttpServer, HttpServerConnectionData;
import dweb.forwarder : Forwarder, ForwarderConnectionData, forwardToHostHandler;

union ServerHandlerUnion
{
    HttpServerConnectionData http;
    ForwarderConnectionData forwarder;
}
struct GlobalServerHooks
{
    enum isGlobal = Yes.isGlobal;
    enum ExtraHandlerDataSize = 104;
}
alias GlobalServerThread = ServerThread!GlobalServerHooks;
struct NonGlobalServerHooks
{
    enum isGlobal = No.isGlobal;
    enum ExtraHandlerDataSize = 4;
}
alias NonGlobalServerThread = ServerThread!NonGlobalServerHooks;

int main(string[] args)
{
    //
    // Test using the Global Server
    //
    if(failed(GlobalServerThread.init()))
    {
        // error already logged
        return 1; // error
    }
    {
        auto listenSocket = createListenSocket(inet_sockaddr(htons(8080), in_addr.any));
        if(listenSocket.isInvalid)
        {
            // error already logged
            return 1;
        }
        if(failed(GlobalServerThread.addReadSocket!Void(listenSocket,
            &HttpServer!GlobalServerThread.globalServerListenCallback, null)))
        {
            // error already logged
            return 1; // fail
        }
    }
    {
        auto listenSocket = createListenSocket(inet_sockaddr(htons(8081), in_addr.any));
        if(listenSocket.isInvalid)
        {
            // error already logged
            return 1;
        }
        Forwarder!GlobalServerThread.addRequestHandler(Forwarder!GlobalServerThread.RequestHandler(
            &forwardToHostHandler!GlobalServerThread
        ));
        if(failed(GlobalServerThread.addReadSocket!Void(listenSocket,
            &Forwarder!GlobalServerThread.globalServerListenCallback, null)))
        {
            // error already logged
            return 1; // fail
        }
    }

    //
    // Test using a server instance
    // Just instantiating this to make sure that it works
    //
    {
        NonGlobalServerThread.ServerThreadStruct server;
        if(failed(server.init()))
        {
            // error already logged
            return 1; // error
        }
    }

    return GlobalServerThread.serverLoop();
}
