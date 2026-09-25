// Minimal BLE test (k.odk): no Cafe audio code at all.
// If coco-pc.html can connect to this ("BLE" -> Cafe-TEST) and gets "HELLO", the Mac/Chrome side is fine
// and the problem is inside the Cafe firmware (memory / registers).
#include <NimBLEDevice.h>
#define NUS_SVC "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
#define NUS_RX  "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
#define NUS_TX  "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"
NimBLECharacteristic *tx;
volatile bool gotP = false;
class SCB : public NimBLEServerCallbacks {
  void onConnect(NimBLEServer *s, NimBLEConnInfo &ci) override { Serial.println("[min] connected"); }
  void onDisconnect(NimBLEServer *s, NimBLEConnInfo &ci, int r) override { Serial.printf("[min] disconnected 0x%X\n", r); }
};
class RCB : public NimBLECharacteristicCallbacks {
  void onWrite(NimBLECharacteristic *c, NimBLEConnInfo &ci) override { gotP = true; }
};
void setup() {
  Serial.begin(115200); delay(500);
  Serial.printf("[min] heap before %u\n", (unsigned)ESP.getFreeHeap());
  NimBLEDevice::init("Cafe-TEST");
  NimBLEServer *srv = NimBLEDevice::createServer();
  srv->setCallbacks(new SCB());
  NimBLEService *svc = srv->createService(NUS_SVC);
  tx = svc->createCharacteristic(NUS_TX, NIMBLE_PROPERTY::NOTIFY);
  svc->createCharacteristic(NUS_RX, NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_NR)->setCallbacks(new RCB());
  svc->start();
  NimBLEAdvertising *adv = NimBLEDevice::getAdvertising();
  NimBLEAdvertisementData ad, sr;
  ad.setFlags(BLE_HS_ADV_F_DISC_GEN | BLE_HS_ADV_F_BREDR_UNSUP);
  ad.addServiceUUID(NUS_SVC);
  sr.setName("Cafe-TEST");
  adv->setAdvertisementData(ad); adv->setScanResponseData(sr);
  adv->start();
  Serial.printf("[min] advertising. heap %u\n", (unsigned)ESP.getFreeHeap());
}
void loop() {
  if (gotP) { gotP = false; tx->notify(std::string("HELLO ble-min\n")); }
  delay(5);
}
