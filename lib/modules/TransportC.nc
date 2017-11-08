#include "../../includes/am_types.h"
#include "../../includes/socket.h"

generic configuration TransportC(){
   provides interface Transport;
}

implementation{
  components new TransportP();
  Transport = TransportP.Transport;

  components new TimerMilliC() as sendTimer;
  components RandomC as Random;
  //components new AMSenderC();

  //Timers


  //Lists
  components new PoolC(sendInfo, 20);
  components new QueueC(sendInfo*, 20);



}
