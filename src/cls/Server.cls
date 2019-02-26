Class Chat.Server Extends %CSP.WebSocket
{
/// Event handler for the <b>PreServer</b> event: this is invoked before
/// starting the WebSockets Server.
/// Changes to the <property>SharedConnection</property> flag must be made here.
Method OnPreServer() As %Status
{
	set ..SharedConnection=1
	set room=$GET(%request.Data("room",1),"default")
	set:room="" room="default"
	if (..WebSocketID'=""){
		set ^ChatApp.WebSockets(..WebSocketID)=""
		set ^ChatApp.Room(..WebSocketID)=room
	} else {
		set ^ChatApp.Error($INCREMENT(^ChatApp.Error),"no websocketid defined")=$HOROLOG 
	}
	
	Quit $$$OK
}

/// The WebSocket Server.  Use the <Method>Read</Method> and <Method>Write</Method> methods
/// to receive data from, and send data to, the client.
/// Call the <Method>EndServer</Method> method to gracefully terminate the WebSocket Server.
/// A WebSocket operating asynchronously (<property>SharedConnection=1</property>) can exit this method (using <b>Quit</B>) and subsequently open the WebSocket using the <Method>OpenServer</Method> method.
Method Server() As %Status
{
 	
	JOB ..StatusUpdate(..WebSocketID)
	for {		
	set data=..Read(.size,.sc,1) 
	 If ($$$ISERR(sc)){
	    if ($$$GETERRORCODE(sc)=$$$CSPWebSocketTimeout) {
	  			//$$$DEBUG("no data")
      	}
      	If ($$$GETERRORCODE(sc)=$$$CSPWebSocketClosed){
	      	kill ^ChatApp.WebSockets(..WebSocketID)
	      	d ..RemoveUser($g(^ChatApp.User(..WebSocketID)))	
	   		kill ^ChatApp.User(..WebSocketID)
	      	Quit  // Client closed WebSocket
      	}
	 } else {
		 if data["User"{
		 	JOB ..AddUser(data,..WebSocketID)
		 }else{
		 	set mid=$INCREMENT(^ChatApp.Message)
		 	set ^ChatApp.Message(mid)=data
	 		JOB ..ProcessMessage(mid)
		 }
		 
	 }
	}
  
	Quit $$$OK
}

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

ClassMethod ProcessMessage(mid As %String)
{
	set msg = ##class(%DynamicObject).%FromJSON($GET(^ChatApp.Message(mid)))
	set msg.Type="Chat"
	
	set msg.Sent=$ZDATETIME($HOROLOG,3)
	set c=$order(^ChatApp.WebSockets(""))
	while (c'="") {
		set ws=..%New()
		set sc=ws.OpenServer(c)
		if $$$ISERR(sc){
			set ^ChatApp.Error($INCREMENT(^ChatApp.Error),"open failed for",c)=sc 
		}
		set sc=ws.Write(msg.%ToJSON())
		set c=$order(^ChatApp.WebSockets(c))
		
	}
}

ClassMethod AddUser(data As %String, wid As %String)
{
	if '$data(^ChatApp.UserUpdate){
		set cu = "[]"
	}else{
		s cu = $g(^ChatApp.UserUpdate)
	}
	
	set nu = ##class(%DynamicObject).%FromJSON(data)
	set ^ChatApp.User(wid)=nu.User
	set cuarr = ##class(%DynamicArray).%FromJSON(cu)
	do cuarr.%Push(nu)
	set update = ##class(%DynamicObject).%New()
	set update.Type = "userlist"
	set update.Users = cuarr
	set ^ChatApp.UserUpdate = cuarr.%ToJSON()
	set c=$o(^ChatApp.WebSockets(""))
	while (c '= ""){
		set ws = ..%New()
		set sc = ws.OpenServer(c)
		if $$$ISERR(sc){
			set ^ChatApp.Error($INCREMENT(^ChatApp.Error),"open failed for",c)=sc
		} 
		set sc = ws.Write(update.%ToJSON())
		if $$$ISERR(sc){
			set ^ChatApp.Error($INCREMENT(^ChatApp.Error),"failed to send data to",c)=sc
		}
		set c = $o(^ChatApp.WebSockets(c))
	}
}

ClassMethod RemoveUser(user As %String)
{
	set cuarr = ##class(%DynamicArray).%FromJSON($get(^ChatApp.UserUpdate))
	for i=0:1:cuarr.%Size()-1{
		if cuarr.%Get(i).User = user{
			do cuarr.%Remove(i)
			quit
		}
	}
	set update = ##class(%DynamicObject).%New()
	set update.Type = "userlist"
	set update.Users = cuarr
	set ^ChatApp.UserUpdate = cuarr.%ToJSON()
	set c=$order(^ChatApp.WebSockets(""))
	while (c '= ""){
		set ws = ..%New()
		set sc = ws.OpenServer(c)
		if $$$ISERR(sc){
			set ^ChatApp.Error($INCREMENT(^ChatApp.Error),"open failed for",c)=sc
		} 
		set sc = ws.Write(update.%ToJSON())
		if $$$ISERR(sc){
			set ^ChatApp.Error($INCREMENT(^ChatApp.Error),"failed to send data to",c)=sc
		}
		set c = $order(^ChatApp.WebSockets(c))
	}
}

ClassMethod BroadCast(text As %String = "testmessage")
{
	set msg=##class(%DynamicObject).%New()
	set msg.Type="Chat"
	set msg.Author="system"
	set msg.Message=$SYSTEM.Encryption.Base64Encode(text)
	set c=$ORDER(^ChatApp.WebSockets(""))
	while (c'="") {
		set ws=..%New()
		set sc=ws.OpenServer(c)
		if $$$ISERR(sc){
			set ^ChatApp.Error($INCREMENT(^ChatApp.Error),"open failed for",c)=sc 
			write "failed opening "_c_" removing",!
			kill ^ChatApp.WebSockets(c)
		}
		set sc=ws.Write(msg.%ToJSON())
		write "written to socket "_c_" status:"_sc,!
		set c=$ORDER(^ChatApp.WebSockets(c))
	}
}
}