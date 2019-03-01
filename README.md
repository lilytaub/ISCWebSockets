# A Tutorial On WebSockets
Most server-client communication on the web is based on a request and response structure. The client sends a request to the server and the server responds to this request. The WebSocket protocol provides a two-way channel of communication between a server and client, allowing servers to send messages to clients without first receiving a request. For more information, see the links below.

* [WebSocket protocol](https://tools.ietf.org/html/rfc6455)

* [WebSockets in InterSystems IRIS documentation](https://docs.intersystems.com/irislatest/csp/docbook/DocBook.UI.Page.cls?KEY=GCGI_websockets)

This tutorial is an update of ["Asynchronous Websockets -- a quick tutorial"](https://community.intersystems.com/post/asynchronous-websockets-quick-tutorial) for Caché 2016.2+ and InterSystems IRIS 2018.1+.
#### *Asynchronous vs Synchronous Operation*

In InterSystems IRIS, a WebSocket connection can be implemented synchronously or asynchronously. How the WebSocket connection between client and server operates is determined by the “SharedConnection” property of the %CSP.WebSocket class.

* SharedConnection=1 : Asynchronous operation

* SharedConnection=0: Synchronous operation

A WebSocket connection between a client and a server hosted on an InterSystems IRIS instance includes a connection between the IRIS instance and the Web Gateway. In synchronous WebSocket operation, each WebSocket connection uses a private channel between the InterSystems IRIS instance and the Web Gateway. In asynchronous WebSocket operation, a group of WebSocket clients share a pool of connections between the IRIS instance and the Web Gateway. The advantage of an asynchronous implementation of WebSockets stands out when one has many clients connecting to the same server, as this implementation does not require that each client be handled by an exclusive connection between the Web Gateway and IRIS instance.

In this tutorial we will be implementing WebSockets asynchronously. Thus, all open chat windows share a pool of connections between the Web Gateway and the IRIS instance that hosts the WebSocket server class.

## Chat Application Overview
The “hello world” of WebSockets is a chat application in which a user can send messages that are broadcast to all users logged into the same chatroom. In this tutorial, the components of the chat application include:

* Server: implemented in a class that extends %CSP.WebSocket

* Client: implemented by a CSP page

The implementation of this chat application will achieve the following:
* Users can broadcast messages to all open chat windows

* Online users will appear in the “Online Users” list of all open chat windows

* Users can change their “nickname” by composing a message starting with the “/nick” keyword and this message will not be broadcast but will update the “Online Users” list

* When users close their chat window they will be removed from the “Online Users” list

## The Client
The client side of our chat application is implemented by a CSP page containing the styling for the chat window, the declaration of the WebSocket connection, WebSocket events and methods that handle communication to and from the server, and helper functions that package messages sent to the server and process incoming messages.

First, we’ll look at how the application initiates the WebSocket connection.

![alt text][wscreate]

The `new` function creates a new instance of the WebSocket class. This opens a WebSocket connection to the server using the "wss” (used if TCP communication is secured using SSL/TLS) or “ws” protocol. The server is specified by the webserver port number of the instance hosting the `Chat.Server` class (contained in the `window.location.host` variable) and the name of the server class. The `ws.onopen` event fires when the WebSocket connection is successfully established.

![alt text][wsopen]

This event updates the header of the chat window to indicate that the client and server are connected.

### *Sending Messages*

When a user sends a message the client CSP page calls the `send`. This function serves as a wrapper around the `ws.send` method, which contains the mechanics for sending the client message to the server specified by the “ws” object.

![alt text][wssend]

The send function packages the information to be sent from client to the server in a JSON object, defining key/value pairs according to the type of information being sent (nickname update or general message). The `btoa` method translates the contents of a message into a base-64 encoded ASCII string.

### *Receiving Messages*

When the client receives a message from the server, the `ws.onmessage` event is triggered.

![alt text][wsonmessage]

Depending on the type of message the client receives (“Chat”, “userlist”, or “status”), the `onmessage` event calls the `wrapmessage` or `wrapuser` to populate the appropriate sections of the chat window with the incoming data. If the incoming message is a status update the status header of the chat window is updated with the WebSocket ID.

### *Additional Client Components*

When there is an error in the communication between the client and the server, the WebSocket `onerror` method is triggered.

![alt text][wsonerror]

This event issues an alert that let’s us know there’s been an error and updates the status header.

The `onclose` method is triggered when the WebSocket connection between the client and server is closed.

![alt text][wsonclose]

The `onclose` event updates the status header again.

## The Server

The server side of the chat application is implemented by the `Chat.Server` class, which extends `%CSP.WebSocket`. Our server class inherits various properties and methods from `%CSP.WebSocket`, a few of which I’ll discuss below. The class also implements custom class methods to process messages from and broadcast messages to the client(s).

### *Before Starting the Server*

The `OnPreServer()` is executed before the WebSocket server is created.

![alt text][wsonpreserver]

This method sets the `SharedConnection` class parameter to 1, indicating that our WebSocket connection will be asynchronous and utilized by multiple processes. The `SharedConnection` parameter can only be changed in the OnPreServer() method. `OnPreServer()` also stores the WebSocket ID associated with the client and corresponding room name in the `^ChatApp.WebSockets` and `^ChatApp.Room` globals respectively.

### *The Server Method*

The main body of logic executed by the server is contained in the `Server()` method.

![alt text][wsserver]

This method reads messages sent from the client (using the `Read` method of the `%CSP.WebSockets` class), adds the received JSON objects to the `^ChatApp.Message` global, and calls the `ProcessMessage()` method to forward the message to all other connected chat windows. When a user closes their chat window (thus terminating the WebSocket connection between that client and the server) the `Server()` method’s call to `Read` returns an error code that evaluates to the macro `$$$CSPWebSocketClosed` and the method proceeds to handle the closure accordingly.

### *Processing and Distributing Messages*

'ProcessMessage()' adds metadata to the incoming chat message and forwards it along to all the other connected chat application clients.

![alt text][wsprocmsg]

`ProcessMessage()` retrieves the incoming chat message from the `^ChatApp.Message` global by the message’s assigned messaged ID (`mid`). This global stores the message and associated data in JSON format, as that is how we are sending and receiving data across our connection to the chat clients. We then user the `%DynamicObject` class to create an IRIS object from the JSON string, allowing us to edit the data before we broadcast the message back to all other connected chat clients. We add a `Type` attribute with the value “Chat,” which the chat client will read in determining how to deal with the incoming message.

`ProcessMessage()` converts the IRIS object back into a JSON string (using the `%ToJSON` method of the `%DynamicObject` class) and pushes out the message to the rest of the chat clients. This is done by getting the WebSocket ID of each client-server connection from the `^ChatApp.WebSockets` global and using the IDs to open a WebSocket server connection (via the `OpenServer` method of the `%CSP.WebSocket` class) to the client. This is possible because our server class implements WebSockets asynchronously – we pull from the existing pool of IRIS-Web Gateway connections and assign it the WebSocket ID that identifies the server’s connection to a specific chat client. Finally, the `Write()` WebSocket method pushes the JSON string representation of the message to the client.

## Conclustion

This chat application demonstrates how to establish WebSocket connections between a client and server hosted by InterSystems IRIS. To further explore developing applications that use WebSockets, you can implement the tracking of online users as described in the “Chat Application Overview” section of this tutorial.

[wscreate]: https://raw.githubusercontent.com/lilytaub/ISCWebSockets/master/Article/WS_create_connection.png "Create WebSocket Connection"
[wsopen]: https://raw.githubusercontent.com/lilytaub/ISCWebSockets/master/Article/WS_onopen.png "Open WebSocket Connection"
[wssend]:https://raw.githubusercontent.com/lilytaub/ISCWebSockets/master/Article/WS_send.png "Send data to server"
[wsonmessage]:https://raw.githubusercontent.com/lilytaub/ISCWebSockets/master/Article/WS_onmessage.png "Client Receives Data"
[wsonerror]:https://raw.githubusercontent.com/lilytaub/ISCWebSockets/master/Article/WS_onerror.png "Error Handling"
[wsonclose]:https://raw.githubusercontent.com/lilytaub/ISCWebSockets/master/Article/WS_onclose.png "Close WebSocket Connection"
[wsonpreserver]:https://raw.githubusercontent.com/lilytaub/ISCWebSockets/master/Article/WS_preserver.png "OnPreServer Method"
[wsserver]:https://raw.githubusercontent.com/lilytaub/ISCWebSockets/master/Article/WS_server.png "Server Method"
[wsprocmsg]:https://raw.githubusercontent.com/lilytaub/ISCWebSockets/master/Article/ws_procmsg.png "Process incoming messages on the server"
