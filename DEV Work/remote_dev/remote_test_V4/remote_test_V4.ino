#include<SPI.h>
#include<nRF24L01.h>
#include<RF24.h>
#include <U8g2lib.h>

#ifdef U8X8_HAVE_HW_SPI
#include <SPI.h>
#endif
#ifdef U8X8_HAVE_HW_I2C
#include <Wire.h>
#endif


RF24 radio(9,10);
const uint64_t pipe[1] = {0xF0F0F0F0E1LL};

int throttle = 0;
byte buzzer_flag = 0;
unsigned long lastTransmission;
unsigned long lastCheck; 
unsigned long buzzer_trigger_time;

byte dead_man_pin = 3;
byte buzzer_pin = 7;
int throttle_pin = A3;
int throttle_mapped;
int tone_val;

struct boardData {
  long fl;
  long fr;
  long rl;
  long rr;
  byte slip;
  byte eject;
};

struct boardData data;

U8G2_SSD1306_128X32_UNIVISION_F_HW_I2C u8g2(U8G2_R0);

void setup(){
  start_screen();
  start_radio();
  start_pins();
  startup_audio();
 }

void(* resetFunc) (void) = 0;

 void loop(){
  read_remote_vals();
  send_data_to_board();
  display_data();
  send_data_to_monitor();
}


void start_screen(){
  u8g2.begin();
  u8g2.setFont(u8g2_font_micro_tr); // choose a suitable font
}

void start_radio(){
  radio.begin();
  delay(100);
  radio.setAutoAck(true);
  radio.enableAckPayload();
  radio.enableDynamicPayloads();
  radio.stopListening();
  radio.openWritingPipe(pipe[0]);
  radio.setRetries(15,15);
}

void start_pins(){
  pinMode(dead_man_pin, INPUT_PULLUP);
  pinMode(buzzer_pin, OUTPUT);
}

void startup_audio(){
  tone(buzzer_pin, 1000);
  delay(100);
  tone(buzzer_pin, 100000);
  delay(100);
  tone(buzzer_pin, 10);
  delay(100);
  tone(buzzer_pin, 1000);
  delay(100);
  noTone(buzzer_pin);
}


void read_remote_vals(){
  if(digitalRead(dead_man_pin) == 0){
    throttle = analogRead(throttle_pin);
    throttle_mapped = map(throttle, 0, 1023, 0, 255);
    
  }

  else{
    throttle = 128;
    throttle_mapped = 128;
  }
  
  
}



void send_data_to_board(){
  if (millis() - lastTransmission >= 50) {
    if(radio.write(&throttle_mapped,sizeof(throttle_mapped))){
      lastTransmission = millis();
      if(radio.isAckPayloadAvailable()){
        radio.read(&data,sizeof(data));
      }
    }  
  }

  if(millis()-lastTransmission > 3000){resetFunc();}
  if(millis()-lastTransmission > 1500){start_radio();}
  
  if(buzzer_flag != 1 && data.slip == 0 || data.eject == 0 || millis() - lastTransmission >=1000){
    buzzer_flag = 1;
    buzzer_trigger_time = millis();
  }

  if(buzzer_flag == 1 && millis() - buzzer_trigger_time < 200){
    if(data.slip == 0){tone_val = 800;}
    if(data.eject == 0){tone_val = 400;}
    else{tone_val = 1000;}
    tone(buzzer_pin, tone_val); 
  }

  else if (buzzer_flag == 1 && millis() - buzzer_trigger_time > 200){
    noTone(buzzer_pin);
    buzzer_flag = 0;
  }
}




void send_data_to_monitor(){
  if(millis()-lastCheck >= 50){
    radio.openWritingPipe(pipe[2]);
    if(radio.write(&data,sizeof(data))){
      lastCheck = millis();
    }
    radio.stopListening();
    radio.openWritingPipe(pipe[0]);
  }
} 


void display_data(){
    u8g2.clearBuffer();          // clear the internal memory
    u8g2.setCursor(0,8);
    u8g2.print(throttle_mapped);
    u8g2.setCursor(0,16);
    u8g2.print("fl: ");
    u8g2.print(data.fl);
    u8g2.print("  fr: ");
    u8g2.print(data.fr);
    u8g2.setCursor(0,24);
    u8g2.print("rl: ");
    u8g2.print(data.rl);
    u8g2.print("  rr: ");
    u8g2.print(data.rr);
    u8g2.setCursor(0,30);
    u8g2.print("sl: ");
    u8g2.print(data.slip);
    u8g2.print("  ej: ");
    u8g2.print(data.eject);
    u8g2.sendBuffer();          // transfer internal memory to the display

}
