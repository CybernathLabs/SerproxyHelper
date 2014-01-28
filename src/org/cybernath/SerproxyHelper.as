package org.cybernath
{
	import flash.desktop.NativeApplication;
	import flash.desktop.NativeProcess;
	import flash.desktop.NativeProcessStartupInfo;
	import flash.events.Event;
	import flash.events.EventDispatcher;
	import flash.events.IEventDispatcher;
	import flash.events.IOErrorEvent;
	import flash.events.NativeProcessExitEvent;
	import flash.events.ProgressEvent;
	import flash.filesystem.File;
	import flash.filesystem.FileMode;
	import flash.filesystem.FileStream;
	
	public class SerproxyHelper extends EventDispatcher
	{
		private var np:NativeProcess;
		private var pathToSerp:String;
		public function SerproxyHelper(pathToSerproxy:String = 'serproxy/serproxy')
		{
			super();
			
			pathToSerp = pathToSerproxy;
		}
		
		public function connect():Array
		{
			// Keeps track of the ArduinoSockets and by extension, the ports associated with each.
			var sockets:Array = [];
			
			// Copy over SERPROXY file.
			var sFile:File = File.applicationDirectory.resolvePath(pathToSerp);
			var copiedSerp:File = File.applicationStorageDirectory.resolvePath('serproxy');
			sFile.copyTo(copiedSerp,true);

			// Build the config file.
			var serproxyConfig:File = File.applicationStorageDirectory.resolvePath('serproxy.cfg');
			
			var cfg:String = 
				'newlines_to_nils=false\n' + 
				'comm_baud=57600\n' + 
				'comm_databits=8\n' +
				'comm_stopbits=1\n' +
				'comm_parity=none\n' +
				'timeout=300\n';

			var coms:Array = getComPorts();
			trace(coms);
			cfg += "comm_ports=";
			for(var j:uint = 0; j < coms.length; j++){
				cfg += ((j > 0)?",":"") + (j+1);
			}
			cfg += "\n";
			
			for(var i:uint = 0; i < coms.length; i++){
				cfg += "serial_device" + (i+1) + "=" + coms[i] + "\n";
				cfg += "net_port" + (i+1) + "=" + (5331+i) + "\n";
				sockets.push(new ArduinoSocket(coms[i],(5331+i)));
			}
			
			// Create & populate the config file
			var fStream:FileStream = new FileStream();
			fStream.open(serproxyConfig,FileMode.WRITE);
			fStream.writeUTFBytes(cfg);
			fStream.close();
			
			var npInfo:NativeProcessStartupInfo = new NativeProcessStartupInfo();
			npInfo.executable = copiedSerp;
			
			np = new NativeProcess();
			
			np.addEventListener(ProgressEvent.STANDARD_OUTPUT_DATA, onOutputData);
			
			np.addEventListener(ProgressEvent.STANDARD_ERROR_DATA, onErrorData);
			np.addEventListener(NativeProcessExitEvent.EXIT, onExit);
			np.addEventListener(IOErrorEvent.STANDARD_OUTPUT_IO_ERROR, onIOError);
			np.addEventListener(IOErrorEvent.STANDARD_ERROR_IO_ERROR, onIOError);
			np.start(npInfo);
			NativeApplication.nativeApplication.addEventListener(Event.EXITING,onExiting);
			
			return sockets;
		}
		
		private function onExiting(evt:Event):void
		{
			if(np.running){
				trace("Quitting Serproxy");
				np.exit();
			}else{
				trace("Serproxy already closed");
			}
		}
		
		private function getComPorts(includeAllSerial:Boolean = false, includeAll:Boolean = false):Array
		{
			// This returns the currently available Arduinos.
			var validComPorts:Array = new Array();
			
			var allDevDevices:Array;
			var devDirectory:File = new File("/dev/");
			var searchRegex:RegExp;
			//if all serial ports allowed
			if(includeAllSerial)
				//get any ports that start with tty. or cu.
				searchRegex = /\/dev\/(tty|cu)\./;
				//otherwise we should just return the arduino ports or all ports
			else
				//so store the arduino port regex, which matches any port that starts with tty.usb
				searchRegex = /\/dev\/cu\.usb/;
			
			//get all the ports
			allDevDevices = devDirectory.getDirectoryListing();
			
			//loop through the ports
			for each (var i:File in allDevDevices) 
			{
				//if we should include all ports or if the native path has a match for our regex
				if (includeAll || i.nativePath.match(searchRegex))
				{
					//save this port reference
					validComPorts.push(i.nativePath);
				}
			}
			
			//return requested ports
			return validComPorts;
		}
		
		private function onOutputData(event:ProgressEvent):void 
		{ 
			trace("Std Output: ", np.standardOutput.readUTFBytes(np.standardOutput.bytesAvailable)); 
			
		}
		private function onErrorData(event:ProgressEvent):void
		{
			var out:String = np.standardError.readUTFBytes(np.standardError.bytesAvailable);
			if(out.indexOf("thread started"))
			{
				trace('Successfully started proxy:',out);
			}else{
				trace("ERROR - ", out);
			}
		}
		
		private function onExit(event:NativeProcessExitEvent):void
		{
			trace("Process exited with: ", event.exitCode);
		}
		
		private function onIOError(event:IOErrorEvent):void
		{
			trace("IOError: ",event.toString());
		}
	}
}