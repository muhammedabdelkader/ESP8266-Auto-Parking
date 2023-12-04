#include <WiFi.h>
#include <WiFiClient.h>
#include <WiFiAP.h>
#include <LiquidCrystal_I2C.h>
#include <DNSServer.h>
#include <WebServer.h>
#include <TimeLib.h>


#ifndef LED_BUILTIN
#define LED_BUILTIN 2   // Set the GPIO pin where you connected your test LED or comment this line out if your dev board has a built-in LED
#define webServerName "*"
#define wifiSSID "ParkingAP"
#define ssidPassword "ParkingPasswordHolder" 
#define webServerPort 80 
#define DNS_PORT 53
#define maxConnections 1 
#define channelId 10
#define hiddenSSID 0
#define monitorSpeed 115200
#endif

// Set these to your desired credentials.
const char *ssid = wifiSSID;
const char *password = ssidPassword;
unsigned long parkingStartTime = 0;
unsigned long parkingDuration = 1800;  // Parking duration in seconds (30 minutes)


// Set Default IP address of gateway
IPAddress apIP(10, 10,10, 1); 
// Set lcd port 
LiquidCrystal_I2C lcd(0x27, 20,4); 
// Setup DNS server 
DNSServer dnsServer;
WiFiClient client ; 
WebServer webServer(webServerPort);
void handleRoot();
void handleSet();
void updateLCD();
void setTimeFromString(const String &timeString);
String formatCurrentTime();
String formatTimeRemaining();


void setup() {
  pinMode(LED_BUILTIN, OUTPUT);

  Serial.begin(monitorSpeed);
  Serial.println();
  Serial.println("Configuring access point...");
  WiFi.softAPConfig(apIP,apIP, IPAddress(255,255,255,0));
  // You can remove the password parameter if you want the AP to be open.
  // a valid password must have more than 7 characters
  if (!WiFi.softAP(ssid, password,channelId,hiddenSSID,maxConnections)) {
    log_e("Soft AP creation failed.");
    while(1);
  }
  
  // default is 60 seconds
  dnsServer.setTTL(300);
  // set which return code will be used for all other domains (e.g. sending
  // ServerFailure instead of NonExistentDomain will reduce number of queries
  // sent by clients)
  // default is DNSReplyCode::NonExistentDomain
  dnsServer.setErrorReplyCode(DNSReplyCode::ServerFailure);
  // start DNS server for a specific domain name
  dnsServer.start(DNS_PORT, webServerName, apIP);
  webServer.on("/", HTTP_GET, handleRoot);
  webServer.on("/set", HTTP_POST, handleSet);
 // simple HTTP server to see that DNS server is working
  webServer.onNotFound([]() {
    String message = "Hello World!\n\n";
    message += "URI: ";
    message += webServer.uri();

    webServer.send(200, "text/plain", message);
  });
  webServer.begin();
  Serial.println("Server started");
  parkingStartTime = now();  // Record the start time of parking
}

void loop() {
  dnsServer.processNextRequest();
  webServer.handleClient();
 // Update LCD every second
  if (millis() % 1000 == 0) {
   // updateLCD(); 
  }
 
}


void updateLCD()
{

  lcd.setCursor(0, 1);
  lcd.print("P-tid:" + formatTimeRemaining());
}

void setTimeFromString(const String &timeString) {
  int hour, minute;
  if (sscanf(timeString.c_str(), "%d:%d", &hour, &minute) == 2) {
    setTime(hour, minute, 0, 1, 1, 1970);  // Set the time with the given hour and minute
    parkingStartTime = now();               // Record the start time of parking
  }
}


String formatCurrentTime() {
  char buffer[10];
  sprintf(buffer, "%02d:%02d", hour(), minute());  // Format the time as HH:MM
  return String(buffer);
}

String formatTimeRemaining() {
  unsigned long elapsedTime = now() - parkingStartTime;
  unsigned long remainingTime = parkingDuration - elapsedTime;

  // Ensure the remaining time is not negative
  if (remainingTime < 0) {
    remainingTime = 0;
  }

  int minutes = remainingTime / 60;
  int seconds = remainingTime % 60;

  // Format the remaining time as a string
  return String(minutes) + " min " + String(seconds) + " sec";
}


void handleRoot() {
  String html = "<html><head>";
  html += "<style>";
  html += "body {font-family: Arial, sans-serif; margin: 0; padding: 0; background-color: #3498db; color: white;}";
  html += ".container {width: 100%; max-width: 600px; margin: auto;}";
  html += "h1 {text-align: center; padding: 20px; background-color: #2c3e50; margin: 0;}";
  html += "form {text-align: center; width: 100%; box-sizing: border-box; padding: 20px;}";
  html += "input, select {width: 100%; padding: 8px; margin: 5px 0; box-sizing: border-box;}";
  html += "footer {text-align: center; padding: 10px; background-color: #2c3e50; position: fixed; bottom: 0; width: 100%;}";
  html += "</style>";  
  html += "<script>";
  html += "function setDefaultTime() { "
          "var now = new Date(); "
          "var formattedTime = now.toTimeString().substring(0, 5); "
          "document.parkingForm.time.value = formattedTime; "
          "}";
  html += "</script>";
  html += "</head><body onload='setDefaultTime();'>";
  html += "<div class='container'>";
  html += "<h1>Parking Counter</h1>";
  html += "<p id='line1'>Waiting User Inputs ...</p>";
  html += "<p id='line2'></p>";  // Empty paragraph for the moving string
  html += "<form name='parkingForm' action='/set' method='post'>";
  html += "Set Current Time: <input type='time' name='time' ><br>";
  html += "Set Parking Duration: ";
  html += "<select name='hours'>";
  for (int i = 0; i <= 12; i++) {
    html += "<option value='" + String(i) + "'>" + String(i) + " hours</option>";
  }
  html += "</select>";
  html += "<select name='minutes'>";
  for (int i = 0; i <= 59; i++) {
    html += "<option value='" + String(i) + "'>" + String(i) + " minutes</option>";
  }
  html += "</select><br>";
  html += "<input type='submit' value='Set'>";
  html += "</form>";
  html += "<script>function updateTimes() { "
          "document.getElementById('line1').innerHTML = 'Waiting User Inputs ...'; "
          "}</script>";
  html += "<script>setInterval(updateTimes, 1000);</script>";
  html += "</div>";
  html += "<footer>&copy; 2023 Muhammed Abdelkader</footer>";
  html += "</body></html>";
  webServer.send(200, "text/html", html);
}

void handleSet() {
  String timeParam = webServer.arg("time");
  String hoursParam = webServer.arg("hours");
  String minutesParam = webServer.arg("minutes");

  setTimeFromString(timeParam);

  int selectedHours = hoursParam.toInt();
  int selectedMinutes = minutesParam.toInt();

  // Ensure the minimum parking duration is 30 minutes
  if (selectedHours == 0 && selectedMinutes < 30) {
    selectedMinutes = 30;
  }

  unsigned long selectedDuration = selectedHours * 3600 + selectedMinutes * 60;
  parkingDuration = selectedDuration;  // Update the parking duration
 
  lcd.setCursor(0, 0);
  lcd.print("Parking: " + formatCurrentTime());

  webServer.sendHeader("Location", "/");
  webServer.send(303);
}
