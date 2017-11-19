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
  int serverIndex;


  command socket_store_t Transport.getSocketArray(socket_t fd)
  {
    return socketArray[fd];
  }

  command void Transport.updateSocketArray(socket_t fd, socket_store_t * socket){
    socketArray[fd] = *(socket);
  }


   command socket_t Transport.socket()
  {

    socket_t fd;
    int i;
    int j;
    int availableSize;
    //bool unused;
    int availableSockets[100];
    int foundSocket;

    // find the number of unused sockets and add into unused array.
    j = 0;
    availableSize = 0;

    for(i = 0; i < 100; i++)
    {
      if(socketArray[i].fd == 255)
      {
        availableSockets[j] = i;
        j++;
        availableSize++;
      }
    }

    // if there's no sockets available, return null
    if(availableSize == 0){
      dbg (COMMAND_CHANNEL, "No sockets available!");
      return NULL;
    }

    // Get random socket fd from the available sockets
    foundSocket = call Random.rand16() %availableSize;

    fd = availableSockets[foundSocket];

    dbg (COMMAND_CHANNEL, "Socket # %hhu now used |  size: %d\n", fd, availableSize);

    return fd;
  }





  command error_t Transport.bind(socket_t fd, socket_addr_t *addr )
  {

    // binding server address and port to socket fd
    socketArray[fd].fd = fd;
    socketArray[fd].src = addr-> port;
    socketArray[fd].srcAddr = addr-> addr;
    socketArray[fd].state = LISTEN;
    serverIndex = fd;

    if(fd != 255)
      return SUCCESS;
    else
      return FALSE;

  }


  command socket_t Transport.accept(socket_t fd, socket_addr_t *addr){
    socket_t acceptedSocket;

    acceptedSocket = call Transport.socket();
    // if there are no sockets available, return null
    if(acceptedSocket == 255)
      return NULL;

    // found a socket, now copy the server socket and update destination and port to
    //the accepted socket

    socketArray[acceptedSocket].fd = fd;
    socketArray[acceptedSocket].src = socketArray[serverIndex].src;
    socketArray[acceptedSocket].srcAddr =socketArray[serverIndex].srcAddr;
    socketArray[acceptedSocket].state = ESTABLISHED;

    socketArray[acceptedSocket].dest.port = addr->port;
    socketArray[acceptedSocket].dest.addr = addr->addr;


    return acceptedSocket;

  }


  command uint16_t Transport.write(socket_t fd, uint8_t *buff, uint16_t bufflen)
  {

  }

  command error_t Transport.receive(pack* package){

  }

  command uint16_t Transport.read(socket_t fd, uint8_t *buff, uint16_t bufflen){

  }

  command error_t Transport.connect(socket_t fd, socket_addr_t * addr){

    int i;
    bool availableSocket = FALSE;

    for(i = 0; i < 100; i++)
    {
      if(socketArray[i].fd == 255)
      {
        availableSocket = TRUE;
      }
    }

    if(availableSocket == TRUE)
      return SUCCESS;
    else
      return FAIL;
  }

  command error_t Transport.close(socket_t fd){

  }

  command error_t Transport.release(socket_t fd){

  }

  command error_t Transport.listen(socket_t fd){

  }




}
