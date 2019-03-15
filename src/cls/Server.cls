Class Chat.Server Extends %CSP.WebSocket
{
/// Event handler for the <b>PreServer</b> event: this is invoked before
/// starting the WebSockets Server.
/// Changes to the <property>SharedConnection</property> flag must be made here.
Method OnPreServer() As %Status
{
	set ..SharedConnection=1
	if (..WebSocketID'=""){
		// The ^Chat.WebSocketConnections global records all the WebSocket IDs of existing server-client connections 
		set ^Chat.WebSocketConnections(..WebSocketID)=""
	} else {
		//The ^Chat.Errors global records error information related to creating, opening, or writing to a WebSocket connection
		set ^Chat.Errors($INCREMENT(^Chat.Errors),"no websocketid defined")=$HOROLOG 
	}
	quit $$$OK
}

/// The WebSocket Server.  Use the <Method>Read</Method> and <Method>Write</Method> methods
/// to receive data from, and send data to, the client.
/// Call the <Method>EndServer</Method> method to gracefully terminate the WebSocket Server.
/// A WebSocket operating asynchronously (<property>SharedConnection=1</property>) can exit this method (using <b>quit</B>) and subsequently open the WebSocket using the <Method>OpenServer</Method> method.
Method Server() As %Status
{
	do ..StatusUpdate(..WebSocketID)
	for {		
	set data=..Read(.size,.sc,1) 
	 if ($$$ISERR(sc)){
	    if ($$$GETERRORCODE(sc)=$$$CSPWebSocketTimeout) {
	  			//$$$DEBUG("no data")
      	}
      	if ($$$GETERRORCODE(sc)=$$$CSPWebSocketClosed){
	      	kill ^Chat.WebSocketConnections(..WebSocketID)
	      	do ..RemoveUser($g(^Chat.Users(..WebSocketID)))	
	   		kill ^Chat.Users(..WebSocketID)
	      	quit  // Client closed WebSocket
      	}
	 }else{
		 if data["User"{
		 	do ..AddUser(data,..WebSocketID)
		 }else{
		 	set mid=$INCREMENT(^Chat.Messages)
		 	// The ^Chat.Messages global stores incoming messages from all clients
		 	set ^Chat.Messages(mid)=data
	 		do ..ProcessMessage(mid)
		 }
	 }
	}
	quit $$$OK
}
///Sends a status update to the client corresponding to the <property>wsid</property> input (WebSocket connection ID) through
///the WebSocket connection.
ClassMethod StatusUpdate(wsid As %String)
{
	set stats=##class(%DynamicObject).%New()
	set stats.Type="Status"
	set stats.Message=$SYSTEM.Encryption.Base64Encode("status update, this shouldn't be processed as message")
	set stats.WSID=wsid
	set ws=..%New()
	set sc=ws.OpenServer(wsid)	
	set sc=ws.Write(stats.%ToJSON())
}
///Broadcasts an incoming message (<property>mid</property) from one chat client to all other
///connected chat clients.
ClassMethod ProcessMessage(mid As %String)
{
	set msg = ##class(%DynamicObject).%FromJSON($GET(^Chat.Messages(mid)))
	set msg.Type="Chat"
	set msg.Sent=$ZDATETIME($HOROLOG,3)
	do ..SendData(msg)
}
///Broadcasts an updated list of active users to all connected chat clients after a user is added. 
///Inputs are the new user <property>data</property> to add and the WebSocket connection ID of the new user.
ClassMethod AddUser(data As %String, wid As %String)
{
	//The ^Chat.UserUpdates global contains an updated array of active users across all chat clients
	if '$data(^Chat.UserUpdates){
		set cu = "[]"
	}else{
		set cu = $g(^Chat.UserUpdates)
	}
	
	set nu = ##class(%DynamicObject).%FromJSON(data)
	//The ^Chat.Users global contains the alias of a user associated with a specific client-server WebSocket connection
	set ^Chat.Users(wid)=nu.User
	set cuarr = ##class(%DynamicArray).%FromJSON(cu)
	do cuarr.%Push(nu)
	set update = ##class(%DynamicObject).%New()
	set update.Type = "userlist"
	set update.Users = cuarr
	set ^Chat.UserUpdates = cuarr.%ToJSON()
	do ..SendData(update)
}
///Broadcasts an updated list of active users to all connected chat clients after a user is removed.
///Input is the <property>user</property> to remove from the active list of users. 
ClassMethod RemoveUser(user As %String)
{
	set cuarr = ##class(%DynamicArray).%FromJSON($get(^Chat.UserUpdates))
	for i = 0:1:cuarr.%Size()-1 {
		if cuarr.%Get(i).User = user { do cuarr.%Remove(i) quit }
	}
	set update = ##class(%DynamicObject).%New()
	set update.Type = "userlist"
	set update.Users = cuarr
	set ^Chat.UserUpdates = cuarr.%ToJSON()
	do ..SendData(update)
}
///This method can be used to broadcast a message from the chat server to all connected chat clients.
/// do ##class(Chat.Server).BroadCast("message")
ClassMethod BroadCast(text As %String = "testmessage")
{
	set msg=##class(%DynamicObject).%New()
	set msg.Type="Chat"
	set msg.Author="system"
	set msg.Message=$SYSTEM.Encryption.Base64Encode(text)
	do ..SendData(msg)
}
///Records error data related to failures to open a WebSocket connection to a chat client
///and to send a message to a chat client.
ClassMethod HandleError(connection As %String, type as %String)
{
	if type = "open"{
		set ^Chat.Errors($INCREMENT(^Chat.Errors),"open failed for",connection)=0 
		write "failed opening "_connection_" removing",!
		kill ^Chat.WebSocketConnections(connection)
	}elseif type = "write"{
		set ^Chat.Errors($INCREMENT(^Chat.Errors),"failed to send data to",connection)=0
	}
}
///Sends data in the form of a %DynamicObject to all connected chat clients.
ClassMethod SendData(data As %DynamicObject)
{
	set c = ""
	for {
		set c = $order(^Chat.WebSocketConnections(c))
		if c="" quit
		set ws = ..%New()
		set sc = ws.OpenServer(c)
		if $$$ISERR(sc) { do ..HandleError(c,"open") } 
		set sc = ws.Write(data.%ToJSON())
		if $$$ISERR(sc) { do ..HandleError(c,"write") }
	}
}
}