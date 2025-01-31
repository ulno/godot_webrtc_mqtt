extends Node

# MQTT client implementation in GDScript
# Based checked https://github.com/pycom/pycom-libraries/blob/master/lib/mqtt/mqtt.py
# and initial work by Alex J Lennon <ajlennon@dynamicdevices.co.uk>

# mosquitto_sub -h test.mosquitto.org -v -t "metest/#"
# mosquitto_pub -h test.mosquitto.org -t "metest/retain" -m "retained message" -r

@export var server = "test.mosquitto.org"
@export var port = 1883
@export var client_id = ""
#var websocketurl = "ws://node-red.dynamicdevices.co.uk:1880/ws/test"
var websocketurl = "ws://test.mosquitto.org:8080/mqtt"
#var websocketurl = "ws://echo.websocket.org"
	
var socket = null
var sslsocket = null
var websocketclient = null
var websocket = null


var ssl = false
var ssl_params = null
var pid = 0
var user = null
var pswd = null
var keepalive = 0
var lw_topic = null
var lw_msg = null
var lw_qos = 0
var lw_retain = false

signal received_message(topic, message)


var receivedbuffer : PackedByteArray = PackedByteArray()

func receivedbufferlength():
	#return socket.get_available_bytes()
	return receivedbuffer.size()
	
func YreceivedbuffernextNbytes(n):
	await get_tree().process_frame
		
	while receivedbufferlength() < n:
		await get_tree().create_timer(0.1).timeout
	#var sv = socket.get_data(n)
	#assert (sv[0] == 0)  # error
	#return sv[1]
	var v = receivedbuffer.slice(0, n) # get chunk of size n

	receivedbuffer = receivedbuffer.slice(n)  # cut off n bytes and keep rest (this includes now below case)
	return v

func Yreceivedbuffernext2byteWord():
	var v = (await YreceivedbuffernextNbytes(2))
	return (v[0]<<8) + v[1]

func Yreceivedbuffernextbyte():
	var nbytes=await YreceivedbuffernextNbytes(1)
	if nbytes == null: return null
	if len(nbytes)<1:
		return null
	return nbytes[0]

func senddata(data):
	if socket != null:
		socket.put_data(data)
	elif sslsocket != null:
		sslsocket.put_data(data)
	elif websocket != null:
		#print("putting packet ", Array(data))
		var E = websocket.put_packet(data)
		assert (E == 0)
	
var in_wait_msg = false
func _process(_delta):
	# if socket != null and socket.is_connected_to_host():
	if socket != null:
		socket.poll()
		if socket.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			var n = socket.get_available_bytes()
			if n != 0:
				var sv = socket.get_data(n)
				assert (sv[0] == 0)  # error code
				receivedbuffer.append_array(sv[1])
			
	elif sslsocket != null:
		if sslsocket.status == StreamPeerTLS.STATUS_CONNECTED or sslsocket.status == StreamPeerTLS.STATUS_HANDSHAKING:
			sslsocket.poll()
			var n = sslsocket.get_available_bytes()
			if n != 0:
				var sv = sslsocket.get_data(n)
				assert (sv[0] == 0)  # error code
				receivedbuffer.append_array(sv[1])

	elif websocketclient != null:
		websocketclient.poll()
		while websocket.get_available_packet_count() != 0:
			print("Packets ", websocket.get_available_packet_count())
			receivedbuffer.append_array(websocket.get_packet())
			#print("nnn ", Array(receivedbuffer))

	if in_wait_msg:
		return
	if receivedbufferlength() <= 0:
		return
	in_wait_msg = true
	while receivedbufferlength() > 0:
		await wait_msg()
	in_wait_msg = false



func websocketexperiment():
	websocketclient = WebSocketClient.new()
	var URL = "ws://node-red.dynamicdevices.co.uk:1880/ws/test"
	var E = websocketclient.connect_to_url(URL)
	print("Err: ", E)
	websocket = websocketclient.get_peer(1)
	while not websocket.is_connected_to_host():
		websocketclient.poll()
		print("connecting to host")
		await get_tree().create_timer(0.1).timeout

	for i in range(5):
		var E2 = websocket.put_packet(PackedByteArray([100,101,102,103,104,105]))
		print("Ersr putpacket: ", E2)
		await get_tree().create_timer(0.5).timeout


func _ready():
	if client_id == "":
		randomize()
		client_id = str(randi())

	if get_name() == "test_mqtt1":
		websocketexperiment()
		
	if get_name() == "test_mqtt":
		var metopic = "metest/"
		set_last_will(metopic+"status", "stopped", true)
		#if await connect_to_server().completed:
		if (await websocket_connect_to_server()):
			publish(metopic+"status", "connected", true)
		else:
			print("mqtt failed to connect")
		##connect("received_message",Callable(self,"received_mqtt"))
		subscribe(metopic+"retain")
		subscribe(metopic+"time")
		for i in range(5):
			print("ii", i)
			await get_tree().create_timer(0.5).timeout
			publish(metopic+"time", "t%d" % i)

func Y_recv_len():
	var n = 0
	var sh = 0
	var b
	while 1:
		b = (await Yreceivedbuffernextbyte())
		n |= (b & 0x7f) << sh
		if not b & 0x80:
			return n
		sh += 7

func set_last_will(topic, msg, retain=false, qos=0):
	assert((0 <= qos) and (qos <= 2))
	assert(topic)
	self.lw_topic = topic
	self.lw_msg = msg
	self.lw_qos = qos
	self.lw_retain = retain

func firstmessagetoserver():
	var clean_session = true
	var msg = PackedByteArray()
	msg.append(0x10);
	msg.append(0x00);
	msg.append(0x00);
	msg.append(0x04);
	msg.append_array("MQTT".to_ascii_buffer());
	msg.append(0x04);
	msg.append(0x02);
	msg.append(0x00);
	msg.append(0x00);

	msg[1] = 10 + 2 + len(self.client_id)
	msg[9] = (1<<1) if clean_session else 0
	if self.user != null:
		msg[1] += 2 + len(self.user) + 2 + len(self.pswd)
		msg[9] |= 0xC0
	if self.keepalive:
		assert(self.keepalive < 65536)
		msg[10] |= self.keepalive >> 8
		msg[11] |= self.keepalive & 0x00FF
	if self.lw_topic:
		msg[1] += 2 + len(self.lw_topic) + 2 + len(self.lw_msg)
		msg[9] |= 0x4 | (self.lw_qos & 0x1) << 3 | (self.lw_qos & 0x2) << 3
		msg[9] |= 1<<5 if self.lw_retain else 0

	msg.append(self.client_id.length() >> 8)
	msg.append(self.client_id.length() & 0xFF)
	msg.append_array(self.client_id.to_ascii_buffer())
	if self.lw_topic:
		msg.append(self.lw_topic.length() >> 8)
		msg.append(self.lw_topic.length() & 0xFF)
		msg.append_array(self.lw_topic.to_ascii_buffer())
		msg.append(self.lw_msg.length() >> 8)
		msg.append(self.lw_msg.length() & 0xFF)
		msg.append_array(self.lw_msg.to_ascii_buffer())
	if self.user != null:
		msg.append(self.user.length() >> 8)
		msg.append(self.user.length() & 0xFF)
		msg.append_array(self.user.to_ascii_buffer())
		msg.append(self.pswd.length() >> 8)
		msg.append(self.pswd.length() & 0xFF)
		msg.append_array(self.pswd.to_ascii_buffer())
	return msg

func connect_to_server(usessl=false):
	assert (server != "")
	if client_id == "":
		client_id = "rr%d" % randi()
	in_wait_msg = true

	socket = StreamPeerTCP.new()
	print("Connecting to %s:%s" % [self.server, self.port])
	socket.connect_to_host(self.server, self.port)
	while not socket.get_status() == StreamPeerTCP.STATUS_CONNECTING:
		await get_tree().create_timer(0.2).timeout
	while socket.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		await get_tree().create_timer(0.2).timeout

	if usessl:
		sslsocket = StreamPeerTLS.new()
		var E3 = sslsocket.connect_to_stream(socket) 
		print("EE3 ", E3)
		
	print("Connected to mqtt broker ", self.server)

	var msg = firstmessagetoserver()
	senddata(msg)
	
	var data = (await YreceivedbuffernextNbytes(4))
	if data == null:
		socket = null
		in_wait_msg = false
		return false
		
	assert(data[0] == 0x20 and data[1] == 0x02)
	if data[2] != 0: # TODO: 2 or 3? Was 3 before, but only gets 2
		print("MQTT exception ", data[3])
		in_wait_msg = false
		return false

	#return data[2] & 1
	in_wait_msg = false
	return true

func websocket_connect_to_server():
	assert (server != "")
	if client_id == "":
		client_id = "rr%d" % randi()
	in_wait_msg = true

	websocketclient = WebSocketClient.new()
	#websocketurl = "ws://node-red.dynamicdevices.co.uk:1880/ws/test"
	var E = websocketclient.connect_to_url(websocketurl, PackedStringArray(["mqttv3.1"])) # , false, PackedStringArray(headers))	
	#var E = websocketclient.connect_to_url(websocketurl)	
	
	print("Err: ", E)

	websocket = websocketclient.get_peer(1)
	while not websocket.is_connected_to_host():
		websocketclient.poll()
		print("connecting to host")
		await get_tree().create_timer(0.1).timeout


	var msg = firstmessagetoserver()

	await get_tree().create_timer(0.5).timeout
	print("Connected to mqtt broker ", self.server)

	
	#print(Array(msg))
	#msg = PackedByteArray([16,46,0,4,77,81,84,84,4,38,0,0,0,10,49,54,49,57,53,53,53,52,53,49,0,13,109,101,116,101,115,116,47,115,116,97,116,117,115,0,7,115,116,111,112,112,101,100])
	#await get_tree().create_timer(0.5).timeout
	senddata(msg)
	#var E1 = websocket.put_packet(msg)
	#websocketclient.poll()
	#assert (E1 == 0)
	
	#while true:
	#	websocketclient.poll()
	#	print("packets available ", websocket.get_available_packet_count())
	#	if websocket.get_available_packet_count() != 0:
	#		print(Array(websocket.get_packet()))
	#	await get_tree().create_timer(0.1).timeout

	
#	var data = (await YreceivedbuffernextNbytes(4)).completed
	var data = await YreceivedbuffernextNbytes(4)
	print("dddd ", data)
	if data == null or len(data) < 4:
		socket = null
		websocket = null
		websocketclient = null
		in_wait_msg = false
		return false
		
	assert(data[0] == 0x20 and data[1] == 0x02)
	if data[3] != 0:
		print("MQTT exception ", data[3])
		in_wait_msg = false
		return false

	#return data[2] & 1
	in_wait_msg = false
	return true

func is_connected_to_server():
	if socket != null and socket.is_connected_to_host():
		return true
	if websocket != null and websocket.is_connected_to_host():
		return true
	return false


func disconnect_from_server():
	senddata(PackedByteArray([0xE0, 0x00]))
	if socket != null:
		socket.disconnect_from_host()

	
func ping():
	senddata(PackedByteArray([0xC0, 0x00]))

func publish(topic, msg, retain=false, qos=0):
	#print("publishing ", topic, " ", msg)
	if socket != null:
		if not socket.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			return
	elif websocket != null:
		if not websocket.is_connected_to_host():
			return
	else:
		return

	var pkt = PackedByteArray()
	# Must be an easier way of doing this...
	pkt.append(0x30);
	pkt.append(0x00);
		
	pkt[0] |= ((1<<1) if qos else 0) | (1 if retain else 0)
	var sz = 2 + len(topic) + len(msg)
	if qos > 0:
		sz += 2
	assert(sz < 2097152)
	var i = 1
	while sz > 0x7f:
		pkt[i] = (sz & 0x7f) | 0x80
		sz >>= 7
		i += 1
		if i + 1 > len(pkt):
			pkt.append(0x00);
	pkt[i] = sz
	
	pkt.append(topic.length() >> 8)
	pkt.append(topic.length() & 0xFF)
	pkt.append_array(topic.to_ascii_buffer())

	if qos > 0:
		self.pid += 1
		pkt.append(self.pid >> 8)
		pkt.append(self.pid & 0xFF)

	pkt.append_array(msg.to_ascii_buffer())
	senddata(pkt)
	
	if qos == 1:
		while 1:
			var op = await self.wait_msg()
			if op == 0x40:
				sz = (await Yreceivedbuffernextbyte())
				assert(sz == 0x02)
				var rcv_pid = (await Yreceivedbuffernext2byteWord())
				if self.pid == rcv_pid:
					return
	elif qos == 2: # not supported
		assert(0) # crash

func subscribe(topic, qos=0):
	self.pid += 1

	var msg = PackedByteArray()
	# Must be an easier way of doing this...
	msg.append(0x82);
	var length = 2 + 2 + topic.length() + 1
	msg.append(length)
	msg.append(self.pid >> 8)
	msg.append(self.pid & 0xFF)
	msg.append(topic.length() >> 8)
	msg.append(topic.length() & 0xFF)
	msg.append_array(topic.to_ascii_buffer())
	msg.append(qos);
	
	senddata(msg)
	
	while 0:
		var op = await self.wait_msg()
		if op == 0x90:
			var data = (await YreceivedbuffernextNbytes(4))
			assert(data[1] == (self.pid >> 8) and data[2] == (self.pid & 0x0F))
			if data[3] == 0x80:
				print("MQTT exception ", data[3])
				return false
			return true

	

# Wait for a single incoming MQTT message and process it.
# Subscribed messages are delivered to a callback previously
# set by super.set_callback() method. Other (internal) MQTT
# messages processed internally.
func wait_msg():
	await get_tree().process_frame
	
	if receivedbufferlength() <= 0:
		return
		
	var res = await Yreceivedbuffernextbyte()

	if res == null:
		return null
	if res == 0:
		return false # raise OSError(-1)
	if res == 0xD0:  # PINGRESP
		var sz = await Yreceivedbuffernextbyte()
		assert(sz == 0)
		return null
	var op = res
	if op & 0xf0 != 0x30:
		return op
	var sz = await Y_recv_len()
	var topic_len = await Yreceivedbuffernext2byteWord()
	var data = await YreceivedbuffernextNbytes(topic_len)
	var topic = data.get_string_from_ascii()
	sz -= topic_len + 2
	var pid
	if op & 6:
		pid = (await Yreceivedbuffernext2byteWord())
		sz -= 2
	data = (await YreceivedbuffernextNbytes(sz))
	# warn: May not want to convert payload as ascii
	var msg = data.get_string_from_ascii()
	
	emit_signal("received_message", topic, msg)
	print("Received message", [topic, msg.substr(0, 100)])
	
#	self.cb(topic, msg)
	if op & 6 == 2:
		var pkt = PackedByteArray()
		pkt.append(0x40);
		pkt.append(0x02);
		pkt.append(pid >> 8);
		pkt.append(pid & 0xFF);
		socket.write(pkt)
	elif op & 6 == 4:
		assert(0)

