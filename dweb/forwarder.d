module dweb.forwarder;

import std.typecons : Flag, Yes, No;
import std.string : startsWith;

import more.types : passfail, passed, failed;
import more.alloc : GCDoubler;
import more.builder : Builder;
import more.net : socket_t, socklen_t, lastError, isInvalid, htons,
                  inet_sockaddr, in_addr, accept, recv, send, shutdown, Shutdown, closesocket;
import more.uri : parseScheme;
import more.httpparser : HttpParser, HttpBadRequestReason;

import dweb.types;
import dweb.log;
import dweb.server : HandlerResult;

// TODO:
// should contain code that can filter requests based
// on some set of criteria, and then forward those requests
// to some other entity
//

/*
enum RequestConditionFlag
{
    host,
    uri,
    method,
}
struct Request
{
    const(char)[] method;
    const(char)[] uri;
    const(char)[] host;
}
*/

// Used for development testing, would probably use GCDoubler in production
struct GCMinimumExpander
{
    static T[] expand(T)(T[] array, size_t preserveSize, size_t neededSize)
        in { assert(array.length < neededSize); } body
    {
        array.length = neededSize;
        return array;
    }
}

template Forwarder(alias ServerAlias)
{
    //static assert(Hooks.isGlobal, "non global not supported yet");
    HandlerResult globalServerListenCallback(ServerAlias.Event!Void event)
    {
        inet_sockaddr from;
        socklen_t fromlen = from.sizeof;

        auto newClient = accept(event.sock, &from);
        if(newClient.isInvalid)
        {
            errorf("accept(s=%s) failed (e=%s)", event.sock, lastError);
            return HandlerResult.errorStopServer;
        }
        logf("received new connection from %s", from);

        auto newClientData = ForwarderConnectionData();
        newClientData.parser.sock = newClient;
        if(failed(ServerAlias.addReadSocket!ForwarderConnectionData
            (newClient, &globalServerDataCallback, &newClientData)))
        {
            // error already logged
            shutdown(newClient, Shutdown.both);
            closesocket(newClient);
            return HandlerResult.errorStopServer;
        }
        return HandlerResult.success;
    }
    HandlerResult globalServerDataCallback(ServerAlias.Event!ForwarderConnectionData event)
    {
        event.parser.fullRequest.makeRoomFor(1); // 1-byte buffer, cool!!!!
        //event.parser.fullRequest.makeRoomFor(500);

        auto length = recv(event.sock, event.parser.fullRequest.available);
        if(length <= 0)
        {
            logf("dataCallback(s=%s) recv returned %s (e=%s)", event.sock, length, lastError);
            shutdown(event.sock, Shutdown.both);
            closesocket(event.sock);
            return HandlerResult.removeSocket;
        }
        //logf("dataCallback(s=%s) read %s bytes of data", sock, length);

        auto saveDataLength = event.parser.fullRequest.dataLength;
        event.parser.fullRequest.dataLength += length;
        event.parser.parse(event.parser.fullRequest.data[saveDataLength..$]);

        if(event.parser.done)
        {
            if(event.parser.host)
            {
                logf("(s=%s) got host \"%s\"", event.sock, event.parser.host);
                return handle(event);
            }
            logf("(s=%s) closing socket", event.sock);
            shutdown(event.sock, Shutdown.both);
            closesocket(event.sock);
            return HandlerResult.removeSocket;
        }

        return HandlerResult.success;
    }

    // TODO: this should be a template.
    //       the handler types should have an "extra" field which is a static byte array
    //       whose size if configured by the template.
    struct RequestHandler
    {
        OptionalHandlerResult function(ServerAlias.Event!ForwarderConnectionData event) handle;
        //RequestConditionFlag flags;
    }
    Builder!(RequestHandler, GCDoubler!20) requestHandlers;
    void addRequestHandler(RequestHandler handler)
    {
        requestHandlers.append(handler);
    }
    // Assumption host is set
    HandlerResult handle(ServerAlias.Event!ForwarderConnectionData event)
    {
        foreach(ref handler; requestHandlers.data)
        {
            auto optionalResult = handler.handle(event);
            if(optionalResult.wasHandled)
            {
                return optionalResult.getResult;
            }
        }
        logf("(s=%s) no handler for this request", event.sock);
        shutdown(event.sock, Shutdown.both);
        closesocket(event.sock);
        return HandlerResult.removeSocket;
    }
}
struct ForwarderConnectionData
{
    HttpParser!HttpParserHooks parser;
}

struct OptionalHandlerResult
{
    private HandlerResult result;
    private bool handled;
    this(HandlerResult result)
    {
        this.result = result;
        this.handled = true;
    }
    @property bool wasHandled() const { return handled; }
    @property HandlerResult getResult() const { return result; }
}
OptionalHandlerResult forwardToHostHandler(alias ServerAlias)(ServerAlias.Event!ForwarderConnectionData event)
{
    logf("forwardToHostHandler not fully implemented");

    shutdown(event.sock, Shutdown.both);
    closesocket(event.sock);
    return OptionalHandlerResult(HandlerResult.removeSocket);
}

private struct HttpParserHooks
{
    alias DataType = char;
    enum SupportPartialData = true;
    enum SupportCallbackStop = true;
    enum MaximumHeaderName = 200;
    enum MaximumMethodName = 100;
    mixin template HttpParserMixinTemplate()
    {
        import more.builder : Builder;
        import more.net : socket_t;
        import dweb.util : Partial;
        // TODO: I could get the sock from the parser pointer
        socket_t sock;

        import dweb.forwarder : GCMinimumExpander;
        Builder!(char,GCMinimumExpander) fullRequest;
        //Builder!(char,GCDoubler!500) fullRequest;

        uint methodLength;
        uint uriLength;

        uint hostHeaderMatchState;
        uint hostHeaderValueOffset;
        uint hostHeaderValueLength;
        string host;
        auto uri() const { return fullRequest.data[methodLength + 1 .. methodLength + 1 + uriLength]; }
    }
    static void onBadRequest(HttpParser!HttpParserHooks* parser, HttpBadRequestReason reason)
    {
        errorf("(s=%s) bad http request: %s", parser.sock, reason);
    }
    static Flag!"stop" onMethodPartial(HttpParser!HttpParserHooks* parser, char[] buffer)
    {
        parser.methodLength += buffer.length;
        return No.stop;
    }
    static Flag!"stop" onMethod(HttpParser!HttpParserHooks* parser, char[] buffer)
    {
        parser.methodLength += buffer.length;
        return No.stop;
    }
    static Flag!"stop" onUriPartial(HttpParser!HttpParserHooks* parser, char[] buffer)
    {
        parser.uriLength += buffer.length;
        return No.stop;
    }
    static immutable SchemesWithHosts = ["http://", "https://"];
    static Flag!"stop" onUri(HttpParser!HttpParserHooks* parser, char[] buffer)
    {
        parser.uriLength += buffer.length;

        // skip scheme
        auto fullUri = parser.uri();
        auto fullUriLimit = fullUri.ptr + fullUri.length;

        size_t schemeLength = parseScheme(fullUri);
        if(schemeLength > 0)
        {
            logf("Scheme \"%s\", URI \"%s\"", fullUri[0..schemeLength], fullUri);
            return Yes.stop; // not implemented
        }
        logf("This uri \"%s\" has no scheme, will use Host header", fullUri);
        return No.stop;
    }
    static Flag!"stop" onHeaderNamePartial(HttpParser!HttpParserHooks* parser, char[] buffer)
    {
        if(parser.hostHeaderMatchState != parser.hostHeaderMatchState.max)
        {
            if("Host"[parser.hostHeaderMatchState..$].startsWith(buffer))
            {
                parser.hostHeaderMatchState += buffer.length;
            }
            else
            {
                parser.hostHeaderMatchState = parser.hostHeaderMatchState.max;
            }
        }
        return No.stop;
    }
    static Flag!"stop" onHeaderName(HttpParser!HttpParserHooks* parser, char[] buffer)
    {
        onHeaderNamePartial(parser, buffer);
        return No.stop;
    }
    static Flag!"stop" onHeaderValuePartial(HttpParser!HttpParserHooks* parser, const(char)[] buffer)
    {
        if(parser.hostHeaderMatchState == "Host".length)
        {
            logf("onHeaderValuePartial: Host value '%s'", buffer);
            if(parser.hostHeaderValueOffset == 0)
            {
                parser.hostHeaderValueOffset = cast(uint)(buffer.ptr - parser.fullRequest.data.ptr);
            }
            parser.hostHeaderValueLength += buffer.length;
        }
        return No.stop;
    }
    static Flag!"stop" onHeaderValue(HttpParser!HttpParserHooks* parser, char[] buffer)
    {
        if(parser.hostHeaderMatchState == "Host".length)
        {
            logf("onHeaderValue      : Host value '%s'", buffer);
            if(parser.hostHeaderValueOffset == 0)
            {
                parser.hostHeaderValueOffset = cast(uint)(buffer.ptr - parser.fullRequest.data.ptr);
            }
            parser.hostHeaderValueLength += buffer.length;
            parser.host = parser.fullRequest.data[parser.hostHeaderValueOffset..parser.hostHeaderValueOffset + parser.hostHeaderValueLength];
            return Yes.stop;
        }
        parser.hostHeaderMatchState = 0;
        return No.stop;
    }
    static void onHeadersDone(HttpParser!HttpParserHooks* parser, char[] buffer)
    {
        if(buffer.length > 0)
        {
            assert(0, "not implemented");
        }
    }
}
