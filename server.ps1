# The port to start the server powershell .\server.ps1 -port 7543
param (
    $port
)

# c sharp code to handle the mouse.

$cSource = @'
using System;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows.Forms;
public class Clicker
{
[StructLayout(LayoutKind.Sequential)]
struct INPUT
{ 
    public int        type; // 0 = INPUT_MOUSE,
                            // 1 = INPUT_KEYBOARD
                            // 2 = INPUT_HARDWARE
    public MOUSEINPUT mi;
}

[StructLayout(LayoutKind.Sequential)]
struct MOUSEINPUT
{
    public int    dx ;
    public int    dy ;
    public int    mouseData ;
    public int    dwFlags;
    public int    time;
    public IntPtr dwExtraInfo;
}

//This covers most use cases although complex mice may have additional buttons
//There are additional constants you can use for those cases, see the msdn page
const int MOUSEEVENTF_MOVED      = 0x0001 ;
const int MOUSEEVENTF_LEFTDOWN   = 0x0002 ;
const int MOUSEEVENTF_LEFTUP     = 0x0004 ;
const int MOUSEEVENTF_RIGHTDOWN  = 0x0008 ;
const int MOUSEEVENTF_RIGHTUP    = 0x0010 ;
const int MOUSEEVENTF_MIDDLEDOWN = 0x0020 ;
const int MOUSEEVENTF_MIDDLEUP   = 0x0040 ;
const int MOUSEEVENTF_WHEEL      = 0x0080 ;
const int MOUSEEVENTF_XDOWN      = 0x0100 ;
const int MOUSEEVENTF_XUP        = 0x0200 ;
const int MOUSEEVENTF_ABSOLUTE   = 0x8000 ;

const int screen_length = 0x10000 ;

[System.Runtime.InteropServices.DllImport("user32.dll")]
extern static uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);

	public static void ClickAtPoint(int x, int y, string b)
	{
		//Move the mouse
		INPUT[] input = new INPUT[3];
		input[0].mi.dx = x*(65535/System.Windows.Forms.Screen.PrimaryScreen.Bounds.Width);
		input[0].mi.dy = y*(65535/System.Windows.Forms.Screen.PrimaryScreen.Bounds.Height);
		input[0].mi.dwFlags = MOUSEEVENTF_MOVED | MOUSEEVENTF_ABSOLUTE;
		
		if(b=="r"){
			//Right mouse button down
			input[1].mi.dwFlags = MOUSEEVENTF_RIGHTDOWN;
			//Right mouse button up
			input[2].mi.dwFlags = MOUSEEVENTF_RIGHTUP;				
		}else{
			//Left mouse button down
			input[1].mi.dwFlags = MOUSEEVENTF_LEFTDOWN;
			//Left mouse button up
			input[2].mi.dwFlags = MOUSEEVENTF_LEFTUP;		
		}
		
		SendInput(3, input, Marshal.SizeOf(input[0]));
	}
	
	
	public static void Move(int x, int y)
	{
		//Move the mouse
		INPUT[] input = new INPUT[1];
		input[0].mi.dx = x*(65535/System.Windows.Forms.Screen.PrimaryScreen.Bounds.Width);
		input[0].mi.dy = y*(65535/System.Windows.Forms.Screen.PrimaryScreen.Bounds.Height);
		input[0].mi.dwFlags = MOUSEEVENTF_MOVED | MOUSEEVENTF_ABSOLUTE;
		
		SendInput(1, input, Marshal.SizeOf(input[0]));
	}		
	
}
'@

Add-Type -TypeDefinition $cSource -ReferencedAssemblies System.Windows.Forms,System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Starts the server
$http = [System.Net.HttpListener]::new() 
$http.Prefixes.Add("http://*:" + $port + "/")
$http.Start()

 
if ($http.IsListening) {
    write-host "Listening on $($http.Prefixes)"
}


while ($http.IsListening) {


    $context = $http.GetContext()

	# Gets the HTML client and returns index.html
    if ($context.Request.HttpMethod -eq 'GET' -and $context.Request.RawUrl -eq '/') {
        write-host "$($context.Request.UserHostAddress)  =>  $($context.Request.Url)" -f 'mag'
		[string]$html = Get-Content "index.html" -Raw
        $buffer = [System.Text.Encoding]::UTF8.GetBytes($html)
        $context.Response.ContentLength64 = $buffer.Length
        $context.Response.OutputStream.Write($buffer, 0, $buffer.Length)
        $context.Response.OutputStream.Close() 
    }
	
	# Gets the screen configuration
    if ($context.Request.HttpMethod -eq 'GET' -and $context.Request.RawUrl -eq '/system') {
		
		$screens = [System.Windows.Forms.Screen]::AllScreens
		$json = ConvertTo-Json $screens -Depth 4
		
		 
		
        $buffer = [System.Text.Encoding]::UTF8.GetBytes($json) 
		$context.Response.ContentType = "application/json"
        $context.Response.ContentLength64 = $buffer.Length
        $context.Response.OutputStream.Write($buffer, 0, $buffer.Length) 
        $context.Response.OutputStream.Close() 
    }
	
	# Gets a screen capture. The client polls this endpoing to refresh the client.
	# i = the index of the screen. If there's only 1, it's 0. 
	# q = quality of the JPEG sent back. Lower is less bandwidth but lower quality.
	
    if ($context.Request.HttpMethod -eq 'GET' -and $context.Request.RawUrl.StartsWith('/screen')) {
		
		$idx = [int]$context.Request.QueryString["i"]
		$quality = [int]$context.Request.QueryString["q"]

		$Screen = [System.Windows.Forms.Screen]::AllScreens[$idx]

		$Width  = $Screen.Bounds.Width
		$Height = $Screen.Bounds.Height
		$Left   = $Screen.Bounds.X
		$Top    = $Screen.Bounds.Y


		$bitmap  = New-Object System.Drawing.Bitmap $Width, $Height
		$graphic = [System.Drawing.Graphics]::FromImage($bitmap)
		$graphic.CopyFromScreen($Left, $Top, 0, 0, $bitmap.Size)
		$stream = New-Object System.IO.MemoryStream
		$allEncoders = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders()
		$encoder = $allEncoders | Where-Object { $_.FormatID -eq [System.Drawing.Imaging.ImageFormat]::Jpeg.Guid }
		$encoderParams = New-Object System.Drawing.Imaging.EncoderParameters 1
		$encoderParams.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter ([System.Drawing.Imaging.Encoder]::Quality, $quality)
		$bitmap.Save($stream, $encoder, $encoderParams)
		$buffer = $stream.ToArray()
		$context.Response.ContentType = "image/jpeg"
		$context.Response.ContentLength64 = $buffer.Length
        $context.Response.OutputStream.Write($buffer, 0, $buffer.Length)
        $context.Response.OutputStream.Close()
    
    }	

	# Handles the mouse click
	# x = the x coord
	# y = the y coord
	# b = the button clicked

    if ($context.Request.HttpMethod -eq 'GET' -and $context.Request.RawUrl.StartsWith('/click')) {

		
		$xClick = [int]$context.Request.QueryString["x"];
		$yClick = [int]$context.Request.QueryString["y"];
		$bClick = $context.Request.QueryString["b"];
		
		[Clicker]::ClickAtPoint($xClick, $yClick, $bClick)				
		
    	[string]$html = 'OK'
        $buffer = [System.Text.Encoding]::UTF8.GetBytes($html)
        $context.Response.ContentLength64 = $buffer.Length
        $context.Response.OutputStream.Write($buffer, 0, $buffer.Length)
        $context.Response.OutputStream.Close() #
    }	
	
	# Handles the mouse mouse
	# x = the x coord
	# y = the y coord
	
    if ($context.Request.HttpMethod -eq 'GET' -and $context.Request.RawUrl.StartsWith('/move')) {
		$xMove = [int]$context.Request.QueryString["x"];
		$yMove = [int]$context.Request.QueryString["y"];
		
		[Clicker]::Move($xClick, $yClick)				
		
    	[string]$html = 'OK'
        $buffer = [System.Text.Encoding]::UTF8.GetBytes($html) 
        $context.Response.ContentLength64 = $buffer.Length
        $context.Response.OutputStream.Write($buffer, 0, $buffer.Length) 
        $context.Response.OutputStream.Close() 
    }	
	
	#handles the keyboard
	# k = the keypressed
	# s = combo keys like ctrl, alt, and shift

    if ($context.Request.HttpMethod -eq 'GET' -and $context.Request.RawUrl.StartsWith('/keyboard')) {
		$k = [string]$context.Request.QueryString["k"]
		$s = [string]$context.Request.QueryString["s"]

		$key = ""

		#maps the JS key codes to .NET key codes

		switch($k){
			"Enter" {$key = "{ENTER}"}
			"Shift" {$key = ""}
			"Escape" {$key = "{ESC}"}
			"Tab" {$key = "{TAB}"}
			"Backspace" {$key = "{BACKSPACE}"}
			"Delete" {$key = "{DELETE}"}
			"ArrowUp" {$key = "{UP}"}
			"ArrowDown" {$key = "{DOWN}"}
			"ArrowLeft" {$key = "{LEFT}"}
			"ArrowRight" {$key = "{RIGHT}"}
			"Home" {$key = "{HOME}"}
			"End" {$key = "{END}"}
			"PageUp" {$key = "{PGUP}"}
			"PageDown" {$key = "{PGDN}"}
			"F1" {$key = "{F1}"}
			"F2" {$key = "{F2}"}
			"F3" {$key = "{F3}"}
			"F4" {$key = "{F4}"}
			"F5" {$key = "{F5}"}
			"F6" {$key = "{F6}"}
			"F7" {$key = "{F7}"}
			"F8" {$key = "{F8}"}
			"F9" {$key = "{F9}"}
			"F10" {$key = "{F10}"}
			"F11" {$key = "{F11}"}
			"F12" {$key = "{F12}"}
			"PrintScreen" {$key = "{PRTSC}"}
			"ScrollLock" {$key = "{SCROLLLOCK}"}
			"Pause" {$key = "{PAUSE}"}
			"Insert" {$key = "{INSERT}"}
			"NumLock" {$key = "{NUMLOCK}"}
			"Clear" {$key = "{CLEAR}"}
			default { $key = $k }

		}		
		
		$key = $s + $key
		write-host "Sending on $($key)"
		
		[System.Windows.Forms.SendKeys]::SendWait($key)
		
    	[string]$html = 'OK'
        $buffer = [System.Text.Encoding]::UTF8.GetBytes($html) 
        $context.Response.ContentLength64 = $buffer.Length
        $context.Response.OutputStream.Write($buffer, 0, $buffer.Length) 
        $context.Response.OutputStream.Close() # close the response		

    }	
	
    if ([Console]::KeyAvailable)
    {
        $keyInfo = [Console]::ReadKey($true)
        break
    }	


} 