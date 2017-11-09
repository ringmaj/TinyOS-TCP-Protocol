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
  //components new AMSenderC(channel);

  //Timers

  TransportP.Random -> Random;


  //Lists
  components new PoolC(sendInfo, 20);
  components new QueueC(sendInfo*, 20);



}


/*#include "../../includes/am_types.h"
#include "../../includes/socket.h"

generic configuration TransportC(int channel){
   provides interface Transport;
}

implementation{
  components new TransportP();
  Transport = TransportP.Transport;

  components new TimerMilliC() as sendTimer;
  components RandomC as Random;
  components new AMSenderC(channel);

  //Timers


  //Lists
  components new PoolC(sendInfo, 20);
  components new QueueC(sendInfo*, 20);



}
*/
