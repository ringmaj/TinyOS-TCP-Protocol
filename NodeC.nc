/**
 * ANDES Lab - University of California, Merced
 * This class provides the basic functions of a network node.
 *
 * @author UCM ANDES Lab
 * @date   2013/09/03
 *
 */

#include <Timer.h>
#include "includes/CommandMsg.h"
#include "includes/packet.h"
//#include "dataStructures/interfaces/Hashmap.nc"	// do I need this?
//#include "dataStructures/modules/HashmapC.nc"	// do I need this?

configuration NodeC{
}
implementation {
    components MainC;

    components Node;
    components new AMReceiverC(AM_PACK) as GeneralReceive;

    Node -> MainC.Boot;

	components  RandomC as Random;
	Node.Random->Random;

	components new TimerMilliC() as myTimerC;	//create a new timer with my alias "myTimerC"
	components new TimerMilliC() as myRandTimerC;
	components new TimerMilliC() as myConstantTimerC;
	components new TimerMilliC() as myLSPTimerC;
	Node.periodicTimer->myTimerC;	// Wire interfact to component
	Node.randomTimer->myRandTimerC;
	Node.constantTimer->myConstantTimerC;
	Node.LSPTimer->myLSPTimerC;

    Node.Receive -> GeneralReceive;

    components ActiveMessageC;
    Node.AMControl -> ActiveMessageC;

    components new SimpleSendC(AM_PACK);
    Node.Sender -> SimpleSendC;

    components CommandHandlerC;
    Node.CommandHandler -> CommandHandlerC;

	components new QueueC(uint16_t, 20);
	Node.q -> QueueC;
}
