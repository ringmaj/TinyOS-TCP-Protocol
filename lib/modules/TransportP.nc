/**
 * ANDES Lab - University of California, Merced
 *
 * @author UCM ANDES Lab
 * @date   2013/09/03
 *
 */
#include "../../includes/packet.h"
#include "../../includes/sendInfo.h"
#include "../../includes/channels.h"
#include "../../includes/socket.h"

generic module TransportP(){
  // provides shows the interface we are implementing. See lib/interface/Transport.nc
  // to see what funcitons we need to implement.
 provides interface Transport;

 uses interface Random;

}

implementation{


  //error_t Transend(uint16_t src, uint16_t dest, pack *message);

  // Use this to intiate a send task. We call this method so we can add
  // a delay between sends. If we don't add a delay there may be collisions.

  socket_store_t socketArray[100];


   command socket_t Transport.socket()
  {

    socket_t fd;
    int i;
    int j;
    int availableSize;
    bool unused;
    int availableSockets[100];
    int foundSocket;

    // find the number of unused sockets and add into unused array.
    j = 0;
    availableSize = 0;

    for(i = 0; i < 100; i++)
    {
      if(socketArray[i].fd == NULL)
      {
        availableSockets[j] = i;
        j++;
        availableSize++;
      }
    }

    // if there's no sockets available, return null
    if(availableSize == 0)
      return NULL;

    // Get random socket fd from the available sockets
    foundSocket = call Random.rand16() %availableSize;

    fd = availableSockets[foundSocket];

    dbg (COMMAND_CHANNEL, "Socket # %hhu now used", fd);

    return fd;
  }





  command error_t Transport.bind(socket_t fd, socket_addr_t *addr )
  {

    socketArray[fd].fd = fd;
    socketArray[fd].dest = *addr;
    socketArray[fd].state = LISTEN;


  }


  command socket_t Transport.accept(socket_t fd){

  }


  command uint16_t Transport.write(socket_t fd, uint8_t *buff, uint16_t bufflen)
  {

  }

  command error_t Transport.receive(pack* package){

  }

  command uint16_t Transport.read(socket_t fd, uint8_t *buff, uint16_t bufflen){

  }

  command error_t Transport.connect(socket_t fd, socket_addr_t * addr){

  }

  command error_t Transport.close(socket_t fd){

  }

  command error_t Transport.release(socket_t fd){

  }

  command error_t Transport.listen(socket_t fd){

  }




}
