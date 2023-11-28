#include <Wire.h>
#include <LiquidCrystal_I2C.h>
#include <ESP8266WiFi.h>
#include <ESP8266WebServer.h>
#include <WiFiClient.h>
#include <DNSServer.h>
#include <TimeLib.h>

#ifndef APSSID

#define APSSID "" // @TODO: Set SSID-Value
#define APPSK "" // @TODO: Set SSI-Password 
#define WebServerHostName "local" //@TODO: Set Local web server name 
#endif

// Set the range limit for the WiFi signal
const int maxTransmitPower = 10; // Adjust based on your needs

// Set the DNS port number 
const byte DNS_PORT = 53;

// Set Default IP address of gateway 
IPAddress apIP(10, 10,10, 1); // @TODO: Change GW IP address 

// Set lcd port 
LiquidCrystal_I2C lcd(0x27, 16, 2); //@TODO: Change according to your screen (port,cells,rows)

// Setup DNS server 
DNSServer dnsServer;

// List of authorized MAC addresses
// @TODO: Add mac addresses here ! The below are example 
const uint8_t authorizedMacAddresses[][6] = {
  {0x00, 0x11, 0x22, 0x33, 0x44, 0x55},
  {0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF}
};


/* Set these to your desired credentials. */
const char *ssid = APSSID;
const char *password = APPSK;

ESP8266WebServer server(80);

unsigned long parkingStartTime = 0;
unsigned long parkingDuration = 1800;  // Parking duration in seconds (30 minutes)

void printConnectedClients();

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
  server.send(200, "text/html", html);
}

void handleSet() {
  String timeParam = server.arg("time");
  String hoursParam = server.arg("hours");
  String minutesParam = server.arg("minutes");

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

  server.sendHeader("Location", "/");
  server.send(303);
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

void updateLCD() {
 
  lcd.setCursor(0, 1);
  lcd.print("P-tid:" + formatTimeRemaining());
}

void setup() {
  delay(1000);
  Serial.begin(115200);
  WiFi.softAPConfig(apIP, apIP, IPAddress(255, 255, 255, 0));

  // Set up Soft AP
  WiFi.softAP(ssid, password , 1, 0);  // Enable WPA2 encryption
  
  // Set WiFi range limit : Can not access far from the car 
  WiFi.setOutputPower(maxTransmitPower);

  dnsServer.setTTL(300);
  dnsServer.setErrorReplyCode(DNSReplyCode::ServerFailure);

  dnsServer.start(DNS_PORT, WebServerHostName, apIP);
  lcd.init();
  lcd.clear();
  lcd.backlight();
  lcd.setCursor(0, 0);
  lcd.print("[!] Waiting .... ");
  server.on("/", HTTP_GET, handleRoot);
  server.on("/set", HTTP_POST, handleSet);
  server.begin();
  printConnectedClients();

  parkingStartTime = now();  // Record the start time of parking
}

void loop() {
  dnsServer.processNextRequest();
  server.handleClient();

  // Update LCD every second
  if (millis() % 1000 == 0) {
    updateLCD();
    printConnectedClients();

  }

}

void printConnectedClients() {
 Serial.println("Connected Devices:");

  // Get the list of connected clients
  struct station_info *stationList = wifi_softap_get_station_info();
  while (stationList != NULL) {
    // Convert the MAC address to a string
    char macAddress[18];
    snprintf(macAddress, sizeof(macAddress), "%02X:%02X:%02X:%02X:%02X:%02X",
             stationList->bssid[0], stationList->bssid[1], stationList->bssid[2],
             stationList->bssid[3], stationList->bssid[4], stationList->bssid[5]);
    Serial.printf("Client: %s\n", macAddress);

    // Check if the connected device is authorized
    bool authorized = false;
    for (const auto &authorizedMac : authorizedMacAddresses) {
      if (memcmp(stationList->bssid, authorizedMac, 6) == 0) {
        authorized = true;
        break;
      }
    }

    if (!authorized) {
      Serial.println("Unauthorized device detected! Disconnecting...");
      // Disconnect all stations (not ideal, but the standard Arduino core doesn't provide a direct API)
      wifi_station_disconnect();
    }

    stationList = STAILQ_NEXT(stationList, next);
  }

  wifi_softap_free_station_info();
  Serial.println();
}

