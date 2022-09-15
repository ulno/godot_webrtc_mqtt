extends Control

# We need to name the things me and other,
# Possibly dynamically name and subscribe without the dropdowns
# localname and remotename, topic subscribing and diagrams
# Make a websocket version of the mqtt, so it can deploy
# Once press button (then disable it)
# comment checked the flow, and include mosquitto_sub commands

var peer = WebRTCPeerConnection.new()
var datachannel = null

var my_partialtopic = ""
var my_topic = ""
var otherguypartialtopic = ""
var otherguytopic = ""
var my_mqttstatus = ""
var otherguystatus = ""

var test1k = PackedByteArray()
var test10k = PackedByteArray()
var test100k = PackedByteArray()

func syncremoteid(i):
	$remote_id/OptionButton.selected = 1-$local_id/OptionButton.selected

func updatemqttport():
	if $mqttbroker/usewebsocket.is_pressed():
		$mqttbroker/port.text = str(8081) if $mqttbroker/usessl.is_pressed() else str(8080)
	else:
		$mqttbroker/port.text = str(8883) if $mqttbroker/usessl.is_pressed() else str(1883)

func ord(char_str: String) -> int:
	return char_str.unicode_at(0)
	
func _ready():
	# $remote_id/OptionButton.items = $local_id/OptionButton.items # TODO: what was supposed to happen here?
	if OS.get_name()=="HTML5":
		$mqttbroker/usewebsocket.button_pressed = true
		$mqttbroker/usewebsocket.disabled = true

	var tarr1k = Array()
	randomize()
	for i in range(1024):
		tarr1k.append((randi()%26)+ord("a"))
	test1k = PackedByteArray(tarr1k)
	for i in range(10):
		test10k.append_array(test1k)
	for i in range(10):
		test100k.append_array(test10k)
	test1k[0] = ord('$')
	test10k[0] = ord('$')
	test100k[0] = ord('$')
		
	$local_id/OptionButton.connect("item_selected",Callable(self,"syncremoteid"))
	$mqttbroker/usewebsocket.connect("pressed",Callable(self,"updatemqttport"))
	$mqttbroker/usessl.connect("pressed",Callable(self,"updatemqttport"))
	$MQTTchat/chatsend.connect("pressed",Callable(self,"mqttchatsend"))
	$WebRTCchat/chatsend.connect("pressed",Callable(self,"webrtcchatsend"))
	$testlatency/testwebrtc.connect("pressed",Callable(self,"testlatency").bind("webrtc"))
	$testlatency/testmqtt.connect("pressed",Callable(self,"testlatency").bind("mqtt"))
	
	syncremoteid(0)
	updatemqttport()
	$mqttconnect.connect("pressed",Callable(self,"mqttconnect"))
	$webrtcconnect.connect("pressed",Callable(self,"webrtcconnect"))

	peer.initialize({"iceServers": [ { "urls": ["stun:stun.l.google.com:19302"] } ] })
	datachannel = peer.create_data_channel("chat", {"id": 1, "negotiated": true})
	peer.connect("session_description_created",Callable(self,"_session_description_created"))
	peer.connect("ice_candidate_created",Callable(self,"_ice_candidate_created"))

func texteditappend(textedit, topic, msg=null):
	var textline = topic
	if msg != null:
		textline = topic + ": " + msg.replace("\n", " ")
		if len(textline) > 43:
			textline = textline.substr(0, 40)+"..."
	textedit.set_line(textedit.get_line_count()-1, textline+"\n")
	textedit.scroll_vertical = textedit.get_line_count() - 3
#	textedit.update() # TODO: check if stil necessary in godot 4
	
func mqttpublish(topic, msg, retain=false):
	texteditappend($msg_pub/TextEdit, topic, msg)
	$mqttnode.publish(topic, msg, retain)

func mqttsubscribe(topic):
	texteditappend($msg_sub/TextEdit, "subscribing", topic)
	$mqttnode.subscribe(topic)

var mmsgn = 1
func mqttchatsend():
	if $MQTTchat/chatmsg.text == "" or $MQTTchat/chatmsg.text == "message #%d from %s"%[mmsgn, my_partialtopic]:
		mmsgn += 1
		$MQTTchat/chatmsg.text = "message #%d from %s"%[mmsgn, my_partialtopic]
	mqttpublish(otherguytopic+"chat", $MQTTchat/chatmsg.text)

var wmsgn = 1000
func webrtcchatsend():
	if $WebRTCchat/chatmsg.text == "" or $WebRTCchat/chatmsg.text == "webrtc-message #%d from %s"%[wmsgn, my_partialtopic]:
		wmsgn += 1
		$WebRTCchat/chatmsg.text = "webrtc-message #%d from %s"%[wmsgn, my_partialtopic]
	var E = datachannel.put_packet($WebRTCchat/chatmsg.text.to_utf8_buffer())
	if E != 0:
		$WebRTCchat/chatrec.text = "put_packet error: %d" % E

var t0startlatency = 0
func testlatency(protocol):
	var testbytes = test1k
	if $testlatency/testsize.selected == 1:
		testbytes = test10k
	elif $testlatency/testsize.selected == 2:
		testbytes = test100k
	
	t0startlatency = Time.get_ticks_msec()
	$testlatency/latencyreport.text = "%d"%t0startlatency
	if protocol == "webrtc":
		var E = datachannel.put_packet(testbytes)
		if E != 0:
			$WebRTCchat/chatrec.text = "put_packet error: %d" % E
	elif protocol == "mqtt":
		$mqttnode.publish(otherguytopic+"chat", testbytes.get_string_from_ascii())


func alertsamenameerror():
	$msg_pub/TextEdit.text = "Someone already connected as "+ my_topic+"\n Please restart and change it first"
	$msg_pub/TextEdit.add_theme_color_override("font_color", Color(1, 0, 0))
	$msg_pub/TextEdit.readonly = false

func mqttconnect():
	# stop any changes to the settings once the connection has started
	$mqttconnect.disabled = true
	$mqttbroker/LineEdit.editable = false
	$mqttbroker/port.editable = false
	$roottopic/LineEdit.editable = false
	$local_id/OptionButton.disabled = true
	$mqttbroker/usewebsocket.disabled = true
	$mqttbroker/usessl.disabled = true
		
	my_partialtopic = $local_id/OptionButton.text
	my_topic = $roottopic/LineEdit.text + "/" + my_partialtopic + "/"
	otherguypartialtopic = $remote_id/OptionButton.text
	otherguytopic = $roottopic/LineEdit.text + "/" + otherguypartialtopic + "/"
	print("My_topic: ", my_topic, " otherguytopic: ", otherguytopic)
		
	$mqttnode.set_last_will(my_topic+"status", "stopped", true)
	$mqttnode.connect("received_message",Callable(self,"received_mqtt"))
	
	if $mqttbroker/usewebsocket.is_pressed():
		var websocketurl = "%s://%s:%d/mqtt" % ["wss" if $mqttbroker/usessl.is_pressed() else "ws", $mqttbroker/LineEdit.text, $mqttbroker/port.text.to_int()]
		await $mqttnode.websocket_connect_to_server()
	else:
		$mqttnode.server = $mqttbroker/LineEdit.text
		$mqttnode.port = $mqttbroker/port.text.to_int()
		await $mqttnode.connect_to_server($mqttbroker/usessl.is_pressed())
	$mqttbroker/usewebsocket.disabled = true
	
	mqttsubscribe(my_topic+"offer")
	mqttsubscribe(my_topic+"answer")
	mqttsubscribe(my_topic+"ice")

	mqttsubscribe(otherguytopic+"status")
	mqttsubscribe(my_topic+"status")
	mqttsubscribe(my_topic+"chat")

	# delay for a second to see if "my" status has already been set as connected by someone else
	await get_tree().create_timer(2.0).timeout
	if my_mqttstatus == "connected":
		alertsamenameerror()
	else:
		mqttpublish(my_topic+"status", "connected", true)


func webrtcconnect():
	var x = peer.create_offer()
	print("peer create offer ", peer, "Error:", x)
	if not $mqttnode.is_connected_to_server():
		$remote_sdp/TextEdit.text = "MQTT not connected, so won't work"

func _process(_delta):
	peer.poll()
	if datachannel != null and datachannel.get_ready_state() == datachannel.STATE_OPEN:
		$WebRTCchat/chatsend.disabled = false
		$testlatency/testwebrtc.disabled = false
		if datachannel.get_available_packet_count() > 0:
			var packet = datachannel.get_packet()
			if packet[0] == ord("$"):
				var E = datachannel.put_packet(("*%d" % len(packet)).to_ascii_buffer())
			elif packet[0] == ord("*"):
				$testlatency/latencyreport.text = "%dms  %s" % [Time.get_ticks_msec() - t0startlatency, packet.get_string_from_ascii()]
			else:
				var wmsg = packet.get_string_from_utf8()
				print("datachannel received: ", wmsg)
				$WebRTCchat/chatrec.text = wmsg
	else:
		$WebRTCchat/chatsend.disabled = true
		$testlatency/testwebrtc.disabled = true
		
func _session_description_created(type, data):
	$webrtcconnect.disabled = true	
	print("_session_description_created ", [type, data.substr(0, 10)])
	$local_sdp/TextEdit.text = data
	peer.set_local_description(type, data)
	mqttpublish(otherguytopic+type, data)
		
func _ice_candidate_created(mid_name, index_name, sdp_name):
	print("_ice_candidate_created ", [mid_name, index_name, sdp_name])
	texteditappend($ice_candidates/TextEdit, "Sent: "+mid_name+", "+str(index_name)+", "+sdp_name)
	mqttpublish(otherguytopic+"ice", JSON.new().stringify([mid_name, index_name, sdp_name]))

func received_mqtt(topic, msg):
	texteditappend($msg_sub/TextEdit, topic, msg)	
	var stopic = topic.split("/")
	print("MQTT RECEIVED: ", stopic, ": ", msg.substr(0, 10))
	if len(stopic) == 3:
		if stopic[2] == "offer":
			$remote_sdp/TextEdit.text = msg
			peer.set_remote_description("offer", msg)
		elif stopic[2] == "answer":
			$remote_sdp/TextEdit.text = msg
			peer.set_remote_description("answer", msg)
		elif stopic[2] == "ice":
			var test_json_conv = JSON.new()
			test_json_conv.parse(msg)
			var js = test_json_conv.get_data()
			texteditappend($ice_candidates/TextEdit, "Rec: "+js[0]+", "+str(js[1])+", "+js[2])
			var e = peer.add_ice_candidate(js[0], js[1], js[2])
			print("ICE error:", e)
		elif stopic[2] == "status":
			if stopic[1] == my_partialtopic:
				print("setting my_mqttstatus to: ", msg)
				if my_mqttstatus == "connected":
					alertsamenameerror()
				my_mqttstatus = msg
			if stopic[1] == otherguypartialtopic:
				print("setting otherguystatus to: ", msg)
				otherguystatus = msg
			var mqttbothwaysgood = (my_mqttstatus == "connected") and (otherguystatus == "connected")
			$MQTTchat/chatsend.disabled = not mqttbothwaysgood
			$testlatency/testmqtt.disabled = not mqttbothwaysgood
		elif stopic[2] == "chat":
			if msg[0] == "$":
				$mqttnode.publish(otherguytopic+"chat", "*%d" % len(msg))
			elif msg[0] == "*":
				$testlatency/latencyreport.text = "%dms  %s" % [Time.get_ticks_msec() - t0startlatency, msg]
			else:
				$MQTTchat/chatrec.text = msg
			


