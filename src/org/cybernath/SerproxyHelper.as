package org.cybernath
{
	import flash.desktop.NativeApplication;
	import flash.desktop.NativeProcess;
	import flash.desktop.NativeProcessStartupInfo;
	import flash.events.Event;
	import flash.events.EventDispatcher;
	import flash.events.IOErrorEvent;
	import flash.events.NativeProcessExitEvent;
	import flash.events.ProgressEvent;
	import flash.filesystem.File;
	import flash.filesystem.FileMode;
	import flash.filesystem.FileStream;
	import flash.system.Capabilities;
	
	public class SerproxyHelper extends EventDispatcher
	{
		private var np:NativeProcess;
		private var pathToSerp:String;
		private var isWindows:Boolean = false;
		private var shuttingDown:Boolean = false;
		
		public function SerproxyHelper(pathToSerproxy:String = '')
		{
			super();
			isWindows = (Capabilities.os.indexOf("Windows") > -1);
			
			if(pathToSerproxy.length == 0){
				// Let's use defaults...
				if(isWindows){
					pathToSerproxy = "serproxy/serproxy.exe";
				}else{
					pathToSerproxy = "serproxy/serproxy";
				}
			}
			
			pathToSerp = pathToSerproxy;
		}
		
		public function connect():Array
		{
			// Keeps track of the ArduinoSockets and by extension, the ports associated with each.
			var coms:Array = [];
			if(isWindows)
			{
				// We're on a windows Machine.
				coms = getComPortsWin();
			}else{
				//Let's assumne Mac
				coms = getComPortsMac();
				
				if(coms.length == 0){
					// If we don't have any USB Arduinos, let's try Bluetooths.
					coms = getComPortsMac(true);
				}
			}
			var sockets:Array = [];
			
			
			
			if(coms.length == 0){
				throw(new Error("No Arduinos Found"));
				return [];
			}
			
			// Copy over SERPROXY file.
			var sFile:File = File.applicationDirectory.resolvePath(pathToSerp);
			// There's probably a better way to determine file name, but I'm in a hurry...
			var copiedSerp:File = File.documentsDirectory.resolvePath('serproxy' + ((isWindows)?".exe":""));
			sFile.copyTo(copiedSerp,true);

			// Build the config file.
			var serproxyConfig:File = File.documentsDirectory.resolvePath('serproxy.cfg');
			
			var cfg:String = '';
			
			if(isWindows){
				cfg = buildWinConfig(coms);
			}else{
				cfg = buildMacConfig(coms);
			}
			// Build up "ArduinoSocket" instances to pass along.
			for(var i:uint = 0; i < coms.length; i++){
				sockets.push(new ArduinoSocket(coms[i],(5331+i)));
			}
			
			trace("CONFIG FILE:",cfg);
			
			// Create & populate the config file
			var fStream:FileStream = new FileStream();
			fStream.open(serproxyConfig,FileMode.WRITE);
			fStream.writeUTFBytes(cfg);
			fStream.close();
			
			var npInfo:NativeProcessStartupInfo = new NativeProcessStartupInfo();
			npInfo.executable = copiedSerp;
			npInfo.workingDirectory = File.documentsDirectory;
			
			np = new NativeProcess();
			
			np.addEventListener(ProgressEvent.STANDARD_OUTPUT_DATA, onOutputData);
			
			np.addEventListener(ProgressEvent.STANDARD_ERROR_DATA, onErrorData);
			np.addEventListener(NativeProcessExitEvent.EXIT, onExit);
			np.addEventListener(IOErrorEvent.STANDARD_OUTPUT_IO_ERROR, onIOError);
			np.addEventListener(IOErrorEvent.STANDARD_ERROR_IO_ERROR, onIOError);
			np.start(npInfo);
			NativeApplication.nativeApplication.addEventListener(Event.EXITING,onExiting);
			//copiedSerp.openWithDefaultApplication();
			return sockets;
		}
		
		private function buildMacConfig(coms:Array):String
		{
			var cfg:String = 	'newlines_to_nils=false\n' + 
				'comm_baud=57600\n' + 
				'comm_databits=8\n' +
				'comm_stopbits=1\n' +
				'comm_parity=none\n' +
				'timeout=3600\n';
			
			cfg += "comm_ports=";
			for(var j:uint = 0; j < coms.length; j++){
				cfg += ((j > 0)?",":"") + (j+1);
			}
			cfg += "\n";
			
			for(var i:uint = 0; i < coms.length; i++){
				cfg += "serial_device" + (i+1) + "=" + coms[i] + "\n";
				cfg += "net_port" + (i+1) + "=" + (5331+i) + "\n";
			}
			return cfg;
		}
		
		private function buildWinConfig(coms:Array):String
		{
			var cfg:String = 	'newlines_to_nils=false' + File.lineEnding +
				'comm_baud=57600' + File.lineEnding +
				'comm_databits=8' + File.lineEnding +
				'comm_stopbits=1' + File.lineEnding +
				'comm_parity=none' + File.lineEnding +
				'timeout=3600' + File.lineEnding ;
			
			cfg += "comm_ports=";
			for(var j:uint = 0; j < coms.length; j++){
				cfg += ((j > 0)?",":"") + coms[j].replace("COM","");
			}
			cfg += File.lineEnding;
			
			for(var i:uint = 0; i < coms.length; i++){
				var comNum:String = coms[i].replace("COM","");
				cfg += "net_port" + comNum + "=" + (5331+i) + File.lineEnding;
			}
			return cfg;
		}
		
		public function onExiting(evt:Event):void
		{
			if(np.running){
				if(evt){
					evt.preventDefault();
					evt.stopPropagation();
				}
				trace("Quitting Serproxy");
				np.exit();
				shuttingDown = true;

			}else{
				trace("Serproxy already closed");
			}
		}
		
		private function getComPortsMac(includeAdafruit:Boolean = false):Array
		{
			// This returns the currently available Arduinos.
			var validComPorts:Array = new Array();
			
			var allDevDevices:Array;
			var devDirectory:File = new File("/dev/");
			var searchRegex:RegExp;
			//if all serial ports allowed
			if(includeAdafruit)
				//get any ports that start with tty. or cu.
//				searchRegex = /\/dev\/(tty|cu)\./;
				searchRegex = /\/dev\/cu\.AdafruitEZ-Link/;
				//otherwise we should just return the arduino ports or all ports
			else
				// so store the arduino port regex, which matches any port that starts with tty.usb
				// Added Adafruit Bluetooth compatibility
				searchRegex = /\/dev\/cu\.usb/;
			
			//get all the ports
			allDevDevices = devDirectory.getDirectoryListing();
			
			//loop through the ports
			for each (var i:File in allDevDevices) 
			{
				//if we should include all ports or if the native path has a match for our regex
				if (i.nativePath.match(searchRegex))
				{
					//save this port reference
					validComPorts.push(i.nativePath);
				}
			}
			
			//return requested ports
			return validComPorts;
		}
		
		private function getComPortsWin():Array
		{
			//TODO: Yeah, Not this...
			return ["COM3"];
		}
		
		private function onOutputData(event:ProgressEvent):void 
		{ 
			trace("Std Output: ", np.standardOutput.readUTFBytes(np.standardOutput.bytesAvailable)); 
			
		}
		private function onErrorData(event:ProgressEvent):void
		{
			var out:String = np.standardError.readUTFBytes(np.standardError.bytesAvailable);
			if(out.indexOf("thread started") > -1)
			{
				trace('Successfully started proxy:',out);
			}else{
				trace("ERROR - ", out);
			}
		}
		
		private function onExit(event:NativeProcessExitEvent):void
		{
			trace("Process exited with: ", event.exitCode);
			if(shuttingDown){
				NativeApplication.nativeApplication.exit();
			}
		}
		
		private function onIOError(event:IOErrorEvent):void
		{
			trace("IOError: ",event.toString());
		}
	}
}