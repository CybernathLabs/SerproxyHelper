package org.cybernath
{
	public class ArduinoSocket
	{
		public var portNumber:Number;
		public var portName:String;
		
		public function ArduinoSocket(pName:String = null,pNumber:Number = NaN)
		{
			portName = pName;
			portNumber = pNumber;
		}
	}
}