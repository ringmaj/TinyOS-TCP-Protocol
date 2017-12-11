/*
 * ANDES Lab - University of California, Merced
 * This class provides the basic functions of a network node.
 *
 * @author UCM ANDES Lab
 * @date	2013/09/03
 *
 */
#include <Timer.h>
//#include <inttypes.h>
#include "includes/command.h"
#include "includes/packet.h"
#include "includes/CommandMsg.h"
#include "includes/sendInfo.h"
#include "includes/channels.h"
#include "includes/socket.h"
//#include "dataStructures/interfaces/Hashmap.nc" // do I need this?
//#include "dataStructures/modules/HashmapC.nc" // do I need this?

/*




What Protocol.h specifies:
PROTOCOL_PING = 0,
PROTOCOL_PINGREPLY = 1,
PROTOCOL_LINKEDSTATE = 2,
PROTOCOL_NAME = 3,
PROTOCOL_TCP= 4,
PROTOCOL_DV = 5,
PROTOCOL_CMD = 99

What I specify:
protocol == 6 : Neighbor discovery packet

*/
int totalNumNodes @C();

module Node{
	uses interface Boot;
	uses interface SplitControl as AMControl;
	uses interface Receive;
	uses interface Random;
	uses interface SimpleSend as Sender;
	uses interface Timer<TMilli> as periodicTimer;//, randomTimer; // Interface that was wired in NodeC.nc
	uses interface Timer<TMilli> as randomTimer;
	uses interface Timer<TMilli> as constantTimer;
	uses interface Timer<TMilli> as LSPTimer;
	uses interface Timer<TMilli> as serverTimer;
	uses interface Timer<TMilli> as clientTimer;
	uses interface Timer<TMilli> as lastFinTimer;

	uses interface CommandHandler;
	uses interface Queue<uint16_t> as q;
	uses interface Queue<unAckedPackets> as ackQ;
	uses interface Pool<uint16_t> as p;

	uses interface Hashmap<uint32_t> as socketHashMap;	// Used to look up "fd" (index of socket in socketArray, to get the socket). Keys are: ((srcPort << 24)|(destPort << 16)|(destAddress)), which is of type uint32_t. Values looked up are "fd" file descriptor, which is of type uint8_t socket_port_t;

	uses interface Transport;


}


/*linkState structure
 --------	node1 node2 node3 node4 node5
 node1		0		1		1		0		1
 node2		1		0		0		0		1
 node3		...	...	...
 */



implementation{ // each node's private variables must be declared here, (or it will only be declared once for all nodes, so they all share the same variable)
	pack sendPackage;





	// Holds current nodes understanding of entire network topology
	//typedef struct routingTable
	//{
		uint8_t routingTableNeighborArray[PACKET_MAX_PAYLOAD_SIZE * 8][PACKET_MAX_PAYLOAD_SIZE * 8];
		uint16_t routingTableNumNodes;
	//} routing;


	//typedef struct forwardingTable
	//{
		uint16_t forwardingTableTo[50];
		uint16_t forwardingTableNext[50];
		uint16_t pathCost[50];

		// max index number for both arrays
		// to[0] | next[0]
		// to[1] | next[1]

		uint16_t forwardingTableNumNodes;


		// Project 3
		// Holds all of the ports that were already initialized by cmdTestServer
		socket_port_t initializedPorts[100];
		// Holds the index for the last port in initializedPorts array
		uint16_t topPort = 0;
		//uint16_t rtt_calc;
		//uint16_t startTime;
		//uint16_t endTime;

		uint16_t nodeDest;
		uint8_t nodeSrcPort;
		uint8_t nodeDestPort;

		uint32_t rcvd_ack_time;	// Timeout, if you haven't received an ack by this time, then the packet is lost, resend. How long the sender should wait for an ACK, before re-sending
		socket_store_t timeOutCheckTuple; // used to check for timeouts

		unAckedPackets timeoutPacketCheck;

		// Project 4
		char name [10] = "myNodeName";


	// Used in neighbor discovery
	uint16_t neighbors [50];
	uint16_t top = 0;	// length of elements in neighbors. How many neighbors are in neighbors. index to add next element in neighbors

	// Used to keep track of previous packages sent, so as to not send them again
	//uint16_t prevTop = 0;	// previous top (when top is reset to 0, previous top will not be
	uint32_t sentPacks [50]; // stores a packet's ((seq<<16) | src)) taken of last 50 previous packets sent. This will help recognize if a packet has already been sent before, so not to send it again. First 16 bits are the packet's seq. Last 16 bits are packet's src
	uint16_t packsSent = 0;	// counts number of packets sent by this node. Is incremented when a new pack is sent. (packsSent % 50) is used as the index of sentPacks to write the newly packet to
	uint16_t mySeqNum = 0; // counts number of packets created by this node (to keep track of duplicate packets). Is incremented when a new packet is created (with makePack). Is used as the sequence number when making a new pack

	// Prototypes

	// Sets the (shiftFromFront)th bit from left, in array "data", to valToSetTo (0 or 1)
	int setBit (uint8_t * data, int shiftFromFront, uint8_t valToSetTo) {
		uint8_t ind;
		uint8_t offset;
		uint8_t mask;

		ind = shiftFromFront / 8; // index of byte in data[] array
		offset = shiftFromFront % 8;; // index of bit in byte to set
		mask = (0b10000000) >> offset;

		//dbg (GENERAL_CHANNEL, "setBit was called\n");
		if (!(valToSetTo == 0 || valToSetTo == 1)) {
		dbg (GENERAL_CHANNEL, "setBit error: setBit can only set a bit to 0 or 1\n");
		return 0;
		}

		if (valToSetTo == 1) {
		// sets the bit to 1
		data[ind] = data[ind]| mask;	// The operation (data[ind] & (~mask)) will clear the "offset"th bit in "ind"th byte, setting it to 0. Then	(_ | mask) sets it to 0 or 1, depending on what the mask bit is
		} else {
		// sets the bit to 0
		data[ind] = data[ind] & (~mask);
		}
		// returns 1 if it set it successfully, 0 otherwise.
		return 1;
	}

	// Sets the (shiftFromFront)th bit from left, in array "data", to valToSetTo (0 or 1)
	int getBit (uint8_t * data, int shiftFromFront) {
		uint8_t ind;
		uint8_t offset;
		uint8_t mask;
		uint8_t bit;

		ind = shiftFromFront / 8; // index of byte in data[] array
		offset = shiftFromFront % 8;; // index of bit in byte to set
		mask = (0b10000000) >> offset;
		bit = data[ind] & mask;

		if (bit) {
		return 1;
		} else {
		return 0;
		}
		// returns 0 or 1 depending on what the bit was. Returns -1 if getting the bit failed
	}

	// Converts the neighbor list from the unordered format in "uint16_t neighbors []" to the Link State Packet format, and writes the LSP at memory address "writeTo"
	int writeLinkStatePack (uint8_t * writeTo) {
		int i;
		//dbg (GENERAL_CHANNEL, "address of writeTo is: %p\n", writeTo);
		//writes the Link State packet in bit format from the neighbors array format (like an array used as a stack)

		// initialize LSP to all 0's
		for (i = 0; i < PACKET_MAX_PAYLOAD_SIZE; i++) {
			writeTo[i] = 0;
		}

		// read the uint16_t neighbors [50] array and write it to the LSP
		for (i = 0; i < top; i++) {
			// Sets the bit in writeTo, that corresponds to the NodeID of the neighbor, to 1.
			// So if the node has 3 neighbors with node ID's of 1, 3, 5, 10 and 11 then the LSP will be:
			//0101010000110000000...padded 0's....(20bytes in packet * 8bits/byte = 160 bits in LSP payload)
			//leftmost bit	corresponds to whether or not the node with and ID of 0 is a neighbor.
			//next bit right corresponds to whether or not the node with and ID of 1 is a neighbor.
			//next bit right corresponds to whether or not the node with and ID of 2 is a neighbor.
			//and so on... to the 160th bit, which corresponds to whether or not the node with an ID of 159 is a neighbor
			//The limitation of this system is that the LSP payload can only deal with node ID's from 0 to 159 (inclusive). 0 <= nodeID <= 159
			// sets a bit in writeTo[], at the position if the node ID (from neighbors[i]), to 1 to indicate that the neighbor is included
			setBit(writeTo, neighbors[i] - 1, 1);
		}


	}

	int readLinkStatePack (uint8_t * arrayTo, uint8_t * payloadFrom) {	// reads the Link State Packet from the bit format to the array format (like a row in the routing table)
		int i;
		dbg (ROUTING_CHANNEL, "Copying LSP from payload into array\n");
		for (i = 0; i < PACKET_MAX_PAYLOAD_SIZE * 8; i++) { // This should run once for each bit in the Link State Packet payload array
		if (getBit(payloadFrom, i) == 1) {
			arrayTo[i] = 1;
		} else {
			//arrayTo[i] = 0;
			// overwrites unidirectional routing
		}
		}
		// return value just indicates whether it reached the end of the payload (every last bit of all (PACKET_MAX_PAYLOAD_SIZE * 8) bits)
		if (i >= PACKET_MAX_PAYLOAD_SIZE * 8) {
		return 1;
		}
		return 0;
	}
	void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t Protocol, uint16_t seq, uint8_t *payload, uint8_t length);

	void sendNeighborDiscoverPack() {
		char text [] = "hi neighbors!"; // length is 2 (3 including null char byte '\0' at end)
		//reset the list to empty every time neighbor discovery is called, then re-add them to list when they respond
		top = 0;
		dbg(NEIGHBOR_CHANNEL, "Discovering Neighbors. Sending packet: ");
		makePack(&sendPackage, TOS_NODE_ID, TOS_NODE_ID, 1, 6, mySeqNum, text, PACKET_MAX_PAYLOAD_SIZE);
		logPack(&sendPackage);
		call Sender.send(sendPackage, AM_BROADCAST_ADDR);	// AM_BROADCAST_ADDR is only used for flooding and neighbor discovery
		sentPacks[packsSent%50] = (((sendPackage.seq) << 16) | sendPackage.src); // keep track of all packs send so as not to send them twice
		packsSent++;
		mySeqNum++;
		// The recieve function will now make a list of everyone who responded to this packet (who forwards it back with TTL=0).
		// Maybe the neighbors can just send it only back to the source instead of to AM_BROADCAST_ADDR to all?
	}

	void printLSP (uint8_t* data, char channel []) {
		//int i;
		//uint8_t arr [PACKET_MAX_PAYLOAD_SIZE];
		//for (i = 0; i < PACKET_MAX_PAYLOAD_SIZE; i++) {
		//	arr[i] = data[i];
		//}
		dbg (channel, "0x%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X\n", data[0], data[1], data[2], data[3], data[4], data[5], data[6], data[7], data[8], data[9], data[10], data[11], data[12], data[13], data[14], data[15], data[16], data[17], data[18], data[19]);
		//dbg (ROUTING_CHANNEL, "%d", getBit(data, 0));
	}


	void sendLSP () {
		uint8_t data [PACKET_MAX_PAYLOAD_SIZE];
		writeLinkStatePack (data);	// Creates and formats the LSP, and stores it in array "data"
		dbg (ROUTING_CHANNEL, "Sending LSP:\n");
		makePack(&sendPackage, TOS_NODE_ID, 0, 21, PROTOCOL_LINKEDSTATE, mySeqNum, data, PACKET_MAX_PAYLOAD_SIZE);
		//logPack(&sendPackage);
		dbg(GENERAL_CHANNEL, "Src: %hhu Dest: %hhu Seq: %hhu TTL: %hhu Protocol: %hhu	Payload:\n", sendPackage.src, sendPackage.dest, sendPackage.seq, sendPackage.TTL, sendPackage.protocol);
		// is this an incompatible pointer type???????????
		printLSP((uint8_t *)(sendPackage.payload), GENERAL_CHANNEL);
		// Update my own Routing table with my own LSP
		readLinkStatePack (&(routingTableNeighborArray[sendPackage.src - 1][0]), (uint8_t *)(sendPackage.payload));
		routingTableNumNodes++;
		call Sender.send(sendPackage, AM_BROADCAST_ADDR); // AM_BROADCAST_ADDR is only used for flooding and neighbor discovery
		sentPacks[packsSent%50] = (((sendPackage.seq) << 16) | sendPackage.src);	// keep track of all packs send so as not to send them twice
		packsSent++;
		mySeqNum++;
	}

	void sendTCP (uint8_t flags, uint16_t destination, uint8_t srcPort, uint8_t destPort, uint32_t seq, uint32_t ack, uint8_t* TCPData, uint8_t dataLength) {	// Establishes a TCP connection from the client to the server by sending an SYN Packet to the server
		// The 8 bits in uint8_t flags are specified as follows: [b1 = SYN][b2 = ACK][b3 = FIN][b4 = DATA][b5 = 0][b6 = 0][b7 = 0][b8 = Special ACK (for TCP setup and teardown)]
		uint8_t payloadArr [PACKET_MAX_PAYLOAD_SIZE];
		uint32_t * ptr = (uint32_t *)(&(payloadArr[3])); //reinterpretcast<uint32_t>();
		//dbg (COMMAND_CHANNEL, "Sending Ack packet from port %hhu to node %hhu at port %hhu \n", srcPort, destination, destPort);
		payloadArr[0] = flags;	// (uses 1 byte) set the leftmost bit, to be the SYN flag. And the 2nd to leftmost bit to be the ACK flag
		payloadArr[1] = srcPort;	// (uses 1 byte)
		payloadArr[2] = destPort;	// (uses 1 byte)

		//dbg (COMMAND_CHANNEL, "seq num is:  %u\n", seq);
		//dbg (COMMAND_CHANNEL, "seq num is: %x\n", seq);

		//memcpy ((uint32_t *)(&(payloadArr[2])), &seq, sizeof(seq));
		memcpy (ptr, &seq, sizeof(seq));	// (uses 4 bytes) copy the TCP seq # into the packet

		//dbg (COMMAND_CHANNEL, "TCP seq written in payload is:  %u\n", *ptr);
		//dbg (COMMAND_CHANNEL, "TCP seq written in payload is: %x\n", *ptr);

		memcpy ((ptr + 1), &ack, sizeof(ack));	// (uses 4 bytes) copy the TCP ack # into the packet

		// Send additional data in this TCP pack
		if (TCPData != NULL && dataLength != 0) {
			// Payload size is only 20 bytes (PACKET_MAX_PAYLOAD_SIZE). We already used 1 bytes for flags, 1 for srcPort, 1 for destPort, 4 for seq, 4 for ack. So we used 11 bytes, and so we only have 20 - 11 = 9 bytes left
			if (dataLength > PACKET_MAX_PAYLOAD_SIZE - 11) {
				dataLength = PACKET_MAX_PAYLOAD_SIZE - 11;	// 11 is the number of bytes used in payload so far. So we have (PACKET_MAX_PAYLOAD_SIZE - 11) bytes left to store things
			}
			memcpy ((uint8_t *)(ptr + 2), TCPData, dataLength);
		}




		makePack (&sendPackage, TOS_NODE_ID, destination, 21, PROTOCOL_TCP, mySeqNum, (uint8_t *)payloadArr, PACKET_MAX_PAYLOAD_SIZE);
		//printTCP(sendPackage);
		dbg(COMMAND_CHANNEL, "Sending a package - Src: %hu Dest: %hu Seq: %hhu TTL: %hhu Protocol: %hhu	Payload:(flag: 0x%.2x, srcPort: %hhu, destPort: %hhu, TCPSeqNum:  %u, TCPAckNum:  %u)\n", sendPackage.src, sendPackage.dest, sendPackage.seq, sendPackage.TTL, sendPackage.protocol, sendPackage.payload[0], sendPackage.payload[1], sendPackage.payload[2], *((uint32_t *)(&(sendPackage.payload[3]))), *((uint32_t *)(&(sendPackage.payload[3])) + 1));
		call Sender.send (sendPackage, forwardingTableNext[destination]);
		sentPacks[packsSent%50] = (((sendPackage.seq) << 16) | sendPackage.src);	// keep track of all packs send so as not to send them twice
		packsSent++;
		mySeqNum++;


		// prints payload in hex (uses little endian)
		//for (seq = 0; seq < PACKET_MAX_PAYLOAD_SIZE; seq++) {
		//	dbg (COMMAND_CHANNEL, "%.2x\n", sendPackage.payload[seq]);
		//}

	}



	void printNeighbors (char channel []) {
		int i;
		dbg (channel, "My %hhu neighbor(s) are:\n", top);
		for (i = 0; i < top; i++) {
			dbg (channel, "%hhu\n", neighbors[i]);
		}
		dbg(channel, "\n");
		dbg(channel, "\n");
	}

	void reply (uint16_t to) {
		char text [] = "got it!\n";
		makePack(&sendPackage, TOS_NODE_ID, to, 21, PROTOCOL_PINGREPLY, mySeqNum, (uint8_t *)text, PACKET_MAX_PAYLOAD_SIZE);
		dbg(GENERAL_CHANNEL, "Sending reply to %hhu", to);
		logPack(&sendPackage);
		//call Sender.send(sendPackage, AM_BROADCAST_ADDR);	// AM_BROADCAST_ADDR is only used for flooding and neighbor discovery
		call Sender.send(sendPackage, forwardingTableNext[to]);	// This is how to forward it only to nextHop
		sentPacks[packsSent%50] = ((sendPackage.seq << 16) | sendPackage.src); // keep track of all packs send so as not to send them twice
		packsSent++;
		mySeqNum++;
	}

	void logPack_command(pack *input){
		dbg(COMMAND_CHANNEL, "Src: %hhu Dest: %hhu Seq: %hhu TTL: %hhu Protocol:%hhu	Payload: %s\n",
		input->src, input->dest, input->seq, input->TTL, input->protocol, input->payload);
	}

	bool anyUnvisited(bool v[], int size){
		int i;
		for(i = 0; i < size; i++)
		{
			if(v[i] == FALSE)
			{
			return TRUE;
			}
		}
		return FALSE;
	}

	void updateForwardingTable(int size){
		int i;
		int j;
		int v;
		int min;
		uint16_t current_neighbor;
		uint16_t nextHop;

		// Stores all visited vertices
		bool visited[size+1];

		// Stores cost from the source to any node cost[i]
		int cost[size+1];

		// Stores previous vertex
		uint16_t prev[size+1];

		// Set all costs to infinity, no previous vertices visited
		for(i = 1; i <= size; i++)
		{
			/*cost[i] = INFINITY;*/
			cost[i] = 99999999999999;
			prev[i] = 0;
			visited[i] = FALSE;
		}

		// Cost from source to source is 0
		cost[TOS_NODE_ID] = 0;
		pathCost[TOS_NODE_ID] = 0;

		// We don't have a node 0, so count it as visited and ignore
		visited[0] = TRUE;

		// Do while there are unvisited nodes
		while(anyUnvisited(visited, size) == TRUE)
		{

			// find the first unvisited node, store cost as min
			for(i = 1; i <= size; i++)
			{
			if(visited[i] == FALSE)
			{
				min = cost[i];
				v = i;
				break;
			}
			}

			// look through the rest of the unvisited nodes, find real min cost and choose that vertex
			for(i = 1; i <= size; i++)
			{
			if(visited[i] == FALSE && cost[i] < min)
			{
				min = cost[i];
				v = i;
			}
			}
			// We now have a current vertex selected, add all of its unvisited neighbors to queue to examine costs
			for(i = 1; i <= size; i++)
			{
			if(routingTableNeighborArray[i-1][v-1] == 1)
			{
				call q.enqueue(i);
			}
			}


			// While the Queue is not empty, look at each neighbor and update the cost if a shorter path is found
			while(!(call q.empty()))
		{
			current_neighbor = call q.dequeue();

			if(cost[v] + 1 < cost[current_neighbor])
			{
				cost[current_neighbor] = cost[v] + 1;
				pathCost[current_neighbor] = cost[v] + 1;
				prev[current_neighbor] = v;
			}
		}

		// Add vertex to visited list, repeat until all nodes are visited
		visited[v] = TRUE;
		}
		/*for(i = 1; i <= size; i++)
		dbg (COMMAND_CHANNEL, "Prev[%d] = %hhu\n", i, prev[i]);*/
		// Traverse the previous visited list in order to find next hop
		for(i = 1; i <= size; i++)
		{
			j = i;

			while(prev[j] != TOS_NODE_ID && prev[j] != 0)
			{
			j = prev[j];

			}

			if(prev[j] == 0)
				nextHop = 0;
			else
				nextHop = j;

			forwardingTableTo[i] = i;
			forwardingTableNext[i] = nextHop;
		}

		// forwarding to a node from itself, should be itself
		forwardingTableNext[TOS_NODE_ID] = TOS_NODE_ID;

	}



	void printRoutingTable(char channel []) {
		int i;
		int j;
		/*
		dbg (COMMAND_CHANNEL, "void printRoutingTable(char channel [])	is printing from channel: %s\n", channel);
			dbg (COMMAND_CHANNEL, "Current Routing Table: routingTableNumNodes = %hhu\n", routingTableNumNodes);
		*/
		i = 1;
		dbg (channel, " %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d\n", i, i+1, i+2, i+3, i+4, i+5, i+6, i+7, i+8,i+9,i+10,i+11,i+12,i+13,i+14,i+15,i+16,i+17,i+18);
		for (i = 0; i <= totalNumNodes; i++) {
			j = 0;
			if(i >= 9) {
				dbg (channel, "%d %hhu %hhu %hhu %hhu %hhu %hhu %hhu %hhu %hhu %hhu %hhu %hhu %hhu %hhu %hhu %hhu %hhu %hhu %hhu %hhu %hhu\n", i+1, routingTableNeighborArray[0][i], routingTableNeighborArray[1][i], routingTableNeighborArray[2][i], routingTableNeighborArray[3][i], routingTableNeighborArray[4][i], routingTableNeighborArray[5][i], routingTableNeighborArray[6][i], routingTableNeighborArray[7][i], routingTableNeighborArray[8][i], routingTableNeighborArray[9][i], routingTableNeighborArray[10][i],routingTableNeighborArray[11][i],routingTableNeighborArray[12][i],routingTableNeighborArray[13][i],routingTableNeighborArray[14][i],routingTableNeighborArray[15][i],routingTableNeighborArray[16][i],routingTableNeighborArray[17][i],routingTableNeighborArray[18][i],routingTableNeighborArray[19][i],routingTableNeighborArray[20][i]);
			} else {
				dbg (channel, "%d  %hhu %hhu %hhu %hhu %hhu %hhu %hhu %hhu %hhu %hhu %hhu %hhu %hhu %hhu %hhu %hhu %hhu %hhu %hhu %hhu %hhu\n", i+1, routingTableNeighborArray[0][i], routingTableNeighborArray[1][i], routingTableNeighborArray[2][i], routingTableNeighborArray[3][i], routingTableNeighborArray[4][i], routingTableNeighborArray[5][i], routingTableNeighborArray[6][i], routingTableNeighborArray[7][i], routingTableNeighborArray[8][i], routingTableNeighborArray[9][i], routingTableNeighborArray[10][i],routingTableNeighborArray[11][i],routingTableNeighborArray[12][i],routingTableNeighborArray[13][i],routingTableNeighborArray[14][i],routingTableNeighborArray[15][i],routingTableNeighborArray[16][i],routingTableNeighborArray[17][i],routingTableNeighborArray[18][i],routingTableNeighborArray[19][i],routingTableNeighborArray[20][i]);
			}
		}
		dbg (channel, "\n");
		dbg (channel, "\n");

		dbg (channel, "Current Forwarding Table:\n");

		for (i = 1; i <= totalNumNodes; i++) {
			if( forwardingTableNext[i] != 0)
				dbg (channel, "To: %hhu	|	Next: %hhu	|	Cost: %hhu	\n", forwardingTableTo[i], forwardingTableNext[i], pathCost[i]);
			else
				dbg (channel, "To: %hhu	|	Next: %s	|	Cost: %hhu	\n", forwardingTableTo[i], "no path", pathCost[i]);
		}
	}


void line(){
	dbg(COMMAND_CHANNEL, "---------------------------------------------------------------------\n");
}

void findTimeOuts(socket_store_t socketTuple){
	int i;
	int timeNow = call clientTimer.getNow();

	dbg (COMMAND_CHANNEL, "\n");
	dbg (COMMAND_CHANNEL, "Node %hhu's received ACKS: \n", TOS_NODE_ID);
	dbg(TRANSPORT_CHANNEL, "Time Now is: %u\n", timeNow);


	for(i = 0; i < socketTuple.transfer; i++)
		{
			dbg(TRANSPORT_CHANNEL, "timeout is: %u\t RTT: %u\n", socketTuple.timeOut[i], socketTuple.RTT);
			if(call clientTimer.getNow() > socketTuple.timeOut[i] && socketTuple.ackReceived[i] == 0) // check if the timeout has passed without receiving an ack.
				socketTuple.ackReceived[i] = 0;
			else
				socketTuple.ackReceived[i] = 1;
		}



		dbg(TRANSPORT_CHANNEL, "AcksReceived:  | %hhu | %hhu | %hhu | %hhu | %hhu |\n", socketTuple.ackReceived[0],socketTuple.ackReceived[1],socketTuple.ackReceived[2],socketTuple.ackReceived[3],socketTuple.ackReceived[4]);
}

void printSockets(){
	int i;
	socket_store_t socketTuple;
	bool areSockets = FALSE;





	dbg (COMMAND_CHANNEL, "\n");
	dbg (COMMAND_CHANNEL, "\n");
	dbg (COMMAND_CHANNEL, "Node %hhu's sockets: \n", TOS_NODE_ID);









	for(i = 0; i < 100; i++)
	{
		socketTuple = call Transport.getSocketArray(i);
		if(socketTuple.fd != 255)
		{
			areSockets = TRUE;
			line();

			switch(socketTuple.state)
			{
				case 0:
					dbg (COMMAND_CHANNEL, "socket: %hhu | Src address: %hhu  | Src port: %hhu  | Dest address: %hhu  | Dest port: %hhu  |  fd: %hhu  |  RTT: %u  |  State: %s\n", i, socketTuple.srcAddr,socketTuple.src,socketTuple.dest.addr, socketTuple.dest.port,socketTuple.fd, socketTuple.RTT, "CLOSED");
					break;

				case 1:
					dbg (COMMAND_CHANNEL, "socket: %hhu | Src address: %hhu  | Src port: %hhu  | Dest address: %hhu  | Dest port: %hhu  |  fd: %hhu  |  RTT: %u  |  State: %s\n", i, socketTuple.srcAddr,socketTuple.src,socketTuple.dest.addr, socketTuple.dest.port,socketTuple.fd, socketTuple.RTT, "LISTEN");
					break;

				case 2:
					dbg (COMMAND_CHANNEL, "socket: %hhu | Src address: %hhu  | Src port: %hhu  | Dest address: %hhu  | Dest port: %hhu  |  fd: %hhu  |  RTT: %u  |  State: %s\n", i, socketTuple.srcAddr,socketTuple.src,socketTuple.dest.addr, socketTuple.dest.port,socketTuple.fd, socketTuple.RTT, "ESTABLISHED");
					break;

				case 3:
					dbg (COMMAND_CHANNEL, "socket: %hhu | Src address: %hhu  | Src port: %hhu  | Dest address: %hhu  | Dest port: %hhu  |  fd: %hhu  |  RTT: %u  |  State: %s\n", i, socketTuple.srcAddr,socketTuple.src,socketTuple.dest.addr, socketTuple.dest.port,socketTuple.fd, socketTuple.RTT, "SYN_SENT");
					break;

				case 4:
					dbg (COMMAND_CHANNEL, "socket: %hhu | Src address: %hhu  | Src port: %hhu  | Dest address: %hhu  | Dest port: %hhu  |  fd: %hhu  |  RTT: %u  |  State: %s\n", i, socketTuple.srcAddr,socketTuple.src,socketTuple.dest.addr, socketTuple.dest.port,socketTuple.fd, socketTuple.RTT, "SYN_RCVD");
					break;

				case 5:
					dbg (COMMAND_CHANNEL, "socket: %hhu | Src address: %hhu  | Src port: %hhu  | Dest address: %hhu  | Dest port: %hhu  |  fd: %hhu  |  RTT: %u  |  State: %s\n", i, socketTuple.srcAddr,socketTuple.src,socketTuple.dest.addr, socketTuple.dest.port,socketTuple.fd, socketTuple.RTT, "FIN_SENT");
					break;

				case 6:
					dbg (COMMAND_CHANNEL, "socket: %hhu | Src address: %hhu  | Src port: %hhu  | Dest address: %hhu  | Dest port: %hhu  |  fd: %hhu  |  RTT: %u  |  State: %s\n", i, socketTuple.srcAddr,socketTuple.src,socketTuple.dest.addr, socketTuple.dest.port,socketTuple.fd, socketTuple.RTT, "FIN_RCVD");
					break;

				case 7:
					dbg (COMMAND_CHANNEL, "socket: %hhu | Src address: %hhu  | Src port: %hhu  | Dest address: %hhu  | Dest port: %hhu  |  fd: %hhu  |  RTT: %u  |  State: %s\n", i, socketTuple.srcAddr,socketTuple.src,socketTuple.dest.addr, socketTuple.dest.port,socketTuple.fd, socketTuple.RTT, "FIN_WAIT_1");
					break;

				case 8:
					dbg (COMMAND_CHANNEL, "socket: %hhu | Src address: %hhu  | Src port: %hhu  | Dest address: %hhu  | Dest port: %hhu  |  fd: %hhu  |  RTT: %u  |  State: %s\n", i, socketTuple.srcAddr,socketTuple.src,socketTuple.dest.addr, socketTuple.dest.port,socketTuple.fd, socketTuple.RTT, "FIN_WAIT_2");
					break;

				case 9:
					dbg (COMMAND_CHANNEL, "socket: %hhu | Src address: %hhu  | Src port: %hhu  | Dest address: %hhu  | Dest port: %hhu  |  fd: %hhu  |  RTT: %u  |  State: %s\n", i, socketTuple.srcAddr,socketTuple.src,socketTuple.dest.addr, socketTuple.dest.port,socketTuple.fd, socketTuple.RTT, "CLOSE_WAIT");
					break;

				case 10:
					dbg (COMMAND_CHANNEL, "socket: %hhu | Src address: %hhu  | Src port: %hhu  | Dest address: %hhu  | Dest port: %hhu  |  fd: %hhu  |  RTT: %u  |  State: %s\n", i, socketTuple.srcAddr,socketTuple.src,socketTuple.dest.addr, socketTuple.dest.port,socketTuple.fd, socketTuple.RTT, "LAST_ACK");
					break;

				case 11:
					dbg (COMMAND_CHANNEL, "socket: %hhu | Src address: %hhu  | Src port: %hhu  | Dest address: %hhu  | Dest port: %hhu  |  fd: %hhu  |  RTT: %u  |  State: %s\n", i, socketTuple.srcAddr,socketTuple.src,socketTuple.dest.addr, socketTuple.dest.port,socketTuple.fd, socketTuple.RTT, "TIME_WAIT");
					break;


			}



			//dbg (COMMAND_CHANNEL, "\n");
			line();
		}

	}

	if(areSockets == FALSE)
	dbg (COMMAND_CHANNEL, "...\n");

	dbg (COMMAND_CHANNEL, "\n");
	dbg (COMMAND_CHANNEL, "\n");
}





	void continueTCPStream (socket_store_t socketTuple) {	// client/sender

		uint8_t * data;
		int i;
		int j;
		int dataBytesInPack = 9; // how many bytes should be copied into the 9 byte data section of the TCP pack payload
		int numPacketsToSend; // stores the number of packets to send
		int tempTimeOut;
		int numOutstandingPackets;

		// holds our packet info for verifying ack received. Holds index #, ack #, and timeout
		unAckedPackets unverifiedPacket;

		// The lastSent is the index for the last byte in the sendBuff sent.
		data = &(socketTuple.sendBuff[socketTuple.lastSent]);


		dbg(TRANSPORT_CHANNEL, "Number of Bytes Sent and Acked: %hhu\n", socketTuple.numberOfBytesSentAndAcked);
		dbg(TRANSPORT_CHANNEL, "Transfer: %hu\n", socketTuple.transfer);

		// if we already have sent the same number of bytes as our transfer, we may have already finished sending. Just wait for the acks to be sent or timeout and resend the packets
		if(socketTuple.numberOfBytesSentAndAcked >= socketTuple.transfer)
		{
			dbg(CLEAN_OUTPUT, "We've already sent %hhu bytes! Wait for the acks or resend later\n", socketTuple.numberOfBytesSentAndAcked);
			return;

		}


		// if there is still data to send, we haven't reached the end of our sendBuffer
		if(socketTuple.numberOfBytesSentAndAcked < socketTuple.transfer){

			// Sending our first packet
			if(socketTuple.numberOfBytesSentAndAcked == 0)
			{
				dbg(TRANSPORT_CHANNEL, "---------------------------------------------------------------------\n");
				dbg (TRANSPORT_CHANNEL, "Beginning transmisson, sending first packet\n");
				socketTuple.theirAdvertisedWindow = 128;
				call Transport.updateSocketArray (socketTuple.fd, &socketTuple);

			}
			//----------------------------------------------------------------------------------------------------------------------------------------

			dbg(TRANSPORT_CHANNEL, "\n");
			dbg(TRANSPORT_CHANNEL, "\n");

			// check if our sendBuffer is full, if it is, change lastSent to 0 and reallocate the sendBuff to fit all of the new data
			if(socketTuple.lastSent >= 128){
				dbg(TRANSPORT_CHANNEL, "SendBuff full, reallocating!\n");
				socketTuple.lastSent = 0;

				// reallocate sendBuff
				j = socketTuple.numberOfBytesSentAndAcked;


				for(i = 0; i < SOCKET_BUFFER_SIZE; i++){
					socketTuple.sendBuff[i] = 0;
				}

				for(i = 0; i < socketTuple.transfer; i++){
					socketTuple.sendBuff[i] = j;
					j++;
				}

				socketTuple.lastSent = 0;
			}

				// Update socket array
				call Transport.updateSocketArray (socketTuple.fd, &socketTuple);


		 //----------------------------------------------------------------------------------------------------------------------------------------


		 // record time that ack should arrive before
		 rcvd_ack_time = call clientTimer.getNow() + socketTuple.RTT;
		 numOutstandingPackets = (socketTuple.numberOfBytesSent - socketTuple.numberOfBytesSentAndAcked)/9;


		 // store the time that the ack should arrive before inside of timeOut[]
		 /*socketTuple.timeOut[socketTuple.lowestUnackedSentByte] = rcvd_ack_time;*/

		 dbg(TRANSPORT_CHANNEL, "current time: %u\n", call clientTimer.getNow());
		 dbg(TRANSPORT_CHANNEL, "timeout: %u\n", rcvd_ack_time);


			// increment last sent since a packet was just sent
			/*socketTuple.lastSent += dataBytesInPack - 1;*/

			//dbg(CLEAN_OUTPUT, "Last sent: %hhu\n", socketTuple.lastSent);

			// Update socket array
			call Transport.updateSocketArray (socketTuple.fd, &socketTuple);


			/*if (9 * socketTuple.sndWndSize < dataBytesInPack) {
				dataBytesInPack = 9 * socketTuple.sndWndSize;
			}*/

			// update the unackedPacket Queue
			unverifiedPacket.index = socketTuple.lastSent;
			unverifiedPacket.lastSent = socketTuple.lastSent;
			unverifiedPacket.seq = socketTuple.seq;
			unverifiedPacket.ack = socketTuple.ack;
			unverifiedPacket.timeOut = rcvd_ack_time;
			unverifiedPacket.bytes = dataBytesInPack;
			unverifiedPacket.data = data;
			unverifiedPacket.destAddr = socketTuple.dest.addr;
			unverifiedPacket.srcPort = socketTuple.src;
			unverifiedPacket.destPort = socketTuple.dest.port;



			// add packet to our ackedQueue, to later check
			/*call ackQ.enqueue(unverifiedPacket);*/
			/*dbg(CLEAN_OUTPUT, "bytes in pack: %u\n", dataBytesInPack);*/
			/*dbg(CLEAN_OUTPUT, "bytes in pack: %u\n", dataBytesInPack);
			dbg(CLEAN_OUTPUT, "transfer: %u\n", socketTuple.transfer);
			dbg(CLEAN_OUTPUT, "numberOfBytesSent: %u\n", socketTuple.lastSent);*/
			// make sure all data unused data don't have any garbage values

//--------------------------------------------------------------------------------------------------------------------------------------------------------------------------


			// if the receiver has enough space to receive our full sending window, then send the packets
			if(socketTuple.theirAdvertisedWindow >= socketTuple.sndWndSize){
				numPacketsToSend = socketTuple.sndWndSize/9; // find the number of packets to send
				tempTimeOut = rcvd_ack_time;


				dbg (TRANSPORT_CHANNEL, "(numberOfBytesSent(%hhu) - numberOfBytesSentAndAcked(%hhu))/9 = %hhu\n", socketTuple.numberOfBytesSent, socketTuple.numberOfBytesSentAndAcked, numOutstandingPackets );

				dbg(CLEAN_OUTPUT, "numOutstandingPackets %d\n", numOutstandingPackets);
				numPacketsToSend -= numOutstandingPackets;
				if(numPacketsToSend <= 0)
					numPacketsToSend = 0;



				for(i = 0; i < numPacketsToSend; i++){

					//calculate how much data should go in pack (at most 9). But may be less if there aren't 9 bytes left to send, or if the window size isn't that big. amount to put in pack = min (9, windowSize, dataLeftToSend)
					if ((socketTuple.transfer - socketTuple.lastSent) < dataBytesInPack) {
						dataBytesInPack = socketTuple.transfer - socketTuple.lastSent;
						dbg("bytes in pack: %u\n", dataBytesInPack);
						for(i = 0; i < 9 - dataBytesInPack + 1; i++)
						socketTuple.sendBuff[socketTuple.lastSent + dataBytesInPack + i] = 0;
					}


					// update the unackedPacket to add to our Queue
					unverifiedPacket.index = socketTuple.lastSent;
					unverifiedPacket.lastSent = socketTuple.lastSent;
					unverifiedPacket.seq = socketTuple.seq;
					unverifiedPacket.ack = socketTuple.ack;
					unverifiedPacket.timeOut = tempTimeOut;
					unverifiedPacket.bytes = dataBytesInPack;
					unverifiedPacket.data = data;
					unverifiedPacket.destAddr = socketTuple.dest.addr;
					unverifiedPacket.srcPort = socketTuple.src;
					unverifiedPacket.destPort = socketTuple.dest.port;
					unverifiedPacket.lastSent = socketTuple.lastSent;

					// update the unackedPacket Queue
					call ackQ.enqueue(unverifiedPacket);


					// Wait 1 RTT and check if the ack has arrived yet, if not resend the packet
					 call clientTimer.startOneShot(tempTimeOut);

					// send the packet
					sendTCP (0b00010000, socketTuple.dest.addr, socketTuple.src, socketTuple.dest.port, socketTuple.seq, socketTuple.ack, data, dataBytesInPack);
					socketTuple.numberOfBytesSent += 9;
					// update the seq and data
					socketTuple.seq += 9;
					socketTuple.lastSent +=9;
					data = &(socketTuple.sendBuff[socketTuple.lastSent]);
					//dbg(CLEAN_OUTPUT, "tempTimer: %u\n", tempTimeOut);
					//dbg(CLEAN_OUTPUT, "tempTimer\n");
					tempTimeOut += 1000;

					dbg(CLEAN_OUTPUT, "SENT %u PACKETS!\n", i+1);
					dbg (TRANSPORT_CHANNEL, "Node %hu sends | (DATA, seq=%u, ack=%u)\n", TOS_NODE_ID, socketTuple.seq, socketTuple.ack);

				}



		}

		else 	// if the receiver doesn't have enough space to receive our full sending window size, send fewer packets

		{

			if( socketTuple.theirAdvertisedWindow < 9){

				// update the unackedPacket Queue
				unverifiedPacket.index = socketTuple.lastSent;
				unverifiedPacket.lastSent = socketTuple.lastSent;
				unverifiedPacket.seq = socketTuple.seq;
				unverifiedPacket.ack = socketTuple.ack;
				unverifiedPacket.timeOut = rcvd_ack_time;
				unverifiedPacket.bytes = dataBytesInPack;
				unverifiedPacket.data = data;
				unverifiedPacket.destAddr = socketTuple.dest.addr;
				unverifiedPacket.srcPort = socketTuple.src;
				unverifiedPacket.destPort = socketTuple.dest.port;

				//calculate how much data should go in pack (at most 9). But may be less if there aren't 9 bytes left to send, or if the window size isn't that big. amount to put in pack = min (9, windowSize, dataLeftToSend)
				if ((socketTuple.transfer - socketTuple.lastSent) < dataBytesInPack) {
					dataBytesInPack = socketTuple.transfer - socketTuple.lastSent;
					dbg("bytes in pack: %u\n", dataBytesInPack);
					for(i = 0; i < 9 - dataBytesInPack + 1; i++)
					socketTuple.sendBuff[socketTuple.lastSent + dataBytesInPack + i] = 0;
				}

				if(socketTuple.theirAdvertisedWindow < dataBytesInPack)
					dataBytesInPack = socketTuple.theirAdvertisedWindow;

				dbg (TRANSPORT_CHANNEL, "(numberOfBytesSent(%hhu) - numberOfBytesSentAndAcked(%hhu))/9 = %hhu\n", socketTuple.numberOfBytesSent, socketTuple.numberOfBytesSentAndAcked, numOutstandingPackets );

				// update the unackedPacket Queue
				call ackQ.enqueue(unverifiedPacket);

				// Wait 1 RTT and check if the ack has arrived yet, if not resend the packet
				 call clientTimer.startOneShot(tempTimeOut);
				dbg(CLEAN_OUTPUT, "SENT %u PACKETS!\n", 1);
				dbg(CLEAN_OUTPUT, "should be less than 9, %hhu\n");
				 dbg (TRANSPORT_CHANNEL, "Node %hu sends | (DATA, seq=%u, ack=%u)\n", TOS_NODE_ID, socketTuple.seq, socketTuple.ack);

				sendTCP (0b00010000, socketTuple.dest.addr, socketTuple.src, socketTuple.dest.port, socketTuple.seq, socketTuple.ack, data, dataBytesInPack);
				socketTuple.numberOfBytesSent += dataBytesInPack;


			}
			else
			{
				// update the number of packets to send
				numPacketsToSend = socketTuple.theirAdvertisedWindow/9;

				numPacketsToSend -= numOutstandingPackets;
				if(numPacketsToSend <= 0)
					numPacketsToSend = 0;


			for(i = 0; i < numPacketsToSend; i++){

				//calculate how much data should go in pack (at most 9). But may be less if there aren't 9 bytes left to send, or if the window size isn't that big. amount to put in pack = min (9, windowSize, dataLeftToSend)
				if ((socketTuple.transfer - socketTuple.lastSent) < dataBytesInPack) {
					dataBytesInPack = socketTuple.transfer - socketTuple.lastSent;
					dbg("bytes in pack: %u\n", dataBytesInPack);
					for(i = 0; i < 9 - dataBytesInPack + 1; i++)
					socketTuple.sendBuff[socketTuple.lastSent + dataBytesInPack + i] = 0;
				}

				dbg (TRANSPORT_CHANNEL, "(numberOfBytesSent(%hhu) - numberOfBytesSentAndAcked(%hhu))/9 = %hhu\n", socketTuple.numberOfBytesSent, socketTuple.numberOfBytesSentAndAcked, numOutstandingPackets );


				// update the unackedPacket to add to our Queue
				unverifiedPacket.index = socketTuple.lastSent;
				unverifiedPacket.lastSent = socketTuple.lastSent;
				unverifiedPacket.seq = socketTuple.seq;
				unverifiedPacket.ack = socketTuple.ack;
				unverifiedPacket.timeOut = tempTimeOut;
				unverifiedPacket.bytes = dataBytesInPack;
				unverifiedPacket.data = data;
				unverifiedPacket.destAddr = socketTuple.dest.addr;
				unverifiedPacket.srcPort = socketTuple.src;
				unverifiedPacket.destPort = socketTuple.dest.port;
				unverifiedPacket.lastSent = socketTuple.lastSent;

				// update the unackedPacket Queue
				call ackQ.enqueue(unverifiedPacket);


				// Wait 1 RTT and check if the ack has arrived yet, if not resend the packet
				 call clientTimer.startOneShot(tempTimeOut);


				// send the packet
				sendTCP (0b00010000, socketTuple.dest.addr, socketTuple.src, socketTuple.dest.port, socketTuple.seq, socketTuple.ack, data, dataBytesInPack);
				socketTuple.numberOfBytesSent += dataBytesInPack;
				// update the seq and data
				socketTuple.seq += 9;
				socketTuple.lastSent +=9;
				data = &(socketTuple.sendBuff[socketTuple.lastSent]);
				//dbg(CLEAN_OUTPUT, "tempTimer: %u\n", tempTimeOut);
				//dbg(CLEAN_OUTPUT, "tempTimer\n");
				tempTimeOut += 1000;
				dbg(CLEAN_OUTPUT, "SENT %u PACKETS!\n", i+1);
				dbg (TRANSPORT_CHANNEL, "Node %hu sends | (DATA, seq=%u, ack=%u)\n", TOS_NODE_ID, socketTuple.seq, socketTuple.ack);

			}

			}



		}


			call Transport.updateSocketArray (socketTuple.fd, &socketTuple);

		}
		else
		{
				dbg(TRANSPORT_CHANNEL, "Done transmitting!\n");
				dbg (CLEAN_OUTPUT,"Bytes sent/acked: %hhu\t Transfer: %hu\n", socketTuple.numberOfBytesSentAndAcked ,socketTuple.transfer);

		}



	}

	event void Boot.booted(){
		int i;
		socket_store_t socketTuple;
		int j;
		uint16_t z;

		uint16_t * array;

		z = 65;
		//socket_store_t socketTuple;


		totalNumNodes++;
		dbg(GENERAL_CHANNEL, "NUM NODES: %d\n", totalNumNodes);

		for(i = 0; i < 100; i++)
		{
			socketTuple = call Transport.getSocketArray(i);
			socketTuple.fd = 255;
			call Transport.updateSocketArray(i,&socketTuple);
		}



		routingTableNumNodes = 0;
		call AMControl.start();
		call periodicTimer.startPeriodic(200000);
		for (i = 0; i < PACKET_MAX_PAYLOAD_SIZE * 8; i++) {
		for (j = 0; j < PACKET_MAX_PAYLOAD_SIZE * 8; j++) {
			routingTableNeighborArray[j][i] = 0;
		}
		}
		//printRoutingTable (COMMAND_CHANNEL);
		call randomTimer.startOneShot((call Random.rand32())%400);	// immediately discover neighbors after random time, on start. So don't need to wait for 1st period.
		call LSPTimer.startOneShot(800 + ((call Random.rand32()) % 400));
		call constantTimer.startOneShot(2000);
	}

	// neighbor discovery is required to put the neigbors in the LSP, and send the neighbor list.
	// recieving the LSP's is required to build the routing table, to understand the topology and do Dijkstra's and find shortest path
	// Doing Dijkstra's and finding shortest path is required to build the forwarding table
	// Having the forwarding table is required to send packets

	// So we need a timeline to ensure everything happens in order. And we need to ensure that sending is done at random times (in certain windows of time). To prevent signal collision and ensure transmission arrives on time

	// Timeline of 1 period (beginning at Boot.booted(), or periodicTimer.fired())
	//[t = 0 milliseconds, Boot.booted called or periodicTimer.fired() called]
	//[0 <= t < 200, neighbor discovery packets sent early, so ]
	//[200 <= t < 400, wait for neighbor discovery packets to arrive, so we know what neighbors we have when we send LSP's]
	//[400 <= t < 600, send LSP's, using neighbor list from neighbor packets that arrived]
	//[600 <= t < 1000, wait for all LSP's to flood network arrive so we know what network topology looks like before updating forwarding table]
	//[t == 1000, update forwarding table]
	//[t == 200000, timer resets, so t = 0 milliseconds]

	event void periodicTimer.fired() {
		call randomTimer.startOneShot((call Random.rand32())%400);
		call LSPTimer.startOneShot(800 + ((call Random.rand32()) % 400));
		call constantTimer.startOneShot(2000);
	}

	event void randomTimer.fired() {
		// Should the LSP's be send first? Or the Neighbor discovery?
		sendNeighborDiscoverPack();
		// pause to let the neighbor discovery packets return
		//call LSPTimer.startOneShot(600);
		//sendLSP();
		// pause to let the neighbor discovery packets return

	}

	event void constantTimer.fired() {
		updateForwardingTable(totalNumNodes);
		// printRoutingTable(ROUTING_CHANNEL);

		routingTableNumNodes = 0;
	}

	event void LSPTimer.fired () {
		sendLSP();
	}

	event void serverTimer.fired () {

	}

// no longer needed
	event void clientTimer.fired () {	// handle timeout. Client has sent a packet, but not been acked yet. So we assume it hasn't arrived at the recipient, and needs to be re-sent
	// get the first element in the unackedQueue
	unAckedPackets resentPacket;

	socket_store_t socketTuple;
	int i;

	if(call ackQ.empty() == TRUE){
		dbg(CLEAN_OUTPUT,"FINISHED, QUEUE IS EMPTY\n");
		return;
	}

	resentPacket =  (call ackQ.element(0));

	i = call socketHashMap.get(((resentPacket.srcPort) << 24)|((resentPacket.destPort) << 16)| resentPacket.destAddr);
	socketTuple = call Transport.getSocketArray(i);



	// if our unackedQueue still has the same starting element, then that means we have reached a timeout, resend the packet from the ackQueue
	if(call clientTimer.getNow() > (call ackQ.element(0)).timeOut)
	{
		dbg (CLEAN_OUTPUT, "LATE! RESENDING\n");
		socketTuple.lastSent = resentPacket.lastSent;
		socketTuple.seq = resentPacket.seq;
		socketTuple.ack = resentPacket.ack;
		call Transport.updateSocketArray(i,&socketTuple);

		continueTCPStream(socketTuple);
	}

	}

	event void lastFinTimer.fired () {

		socket_store_t socketTuple;
		int i;
		i = call socketHashMap.get(((nodeSrcPort) << 24)|((nodeDestPort) << 16)| nodeDest);


		// look up seq and ack number
		dbg(COMMAND_CHANNEL, "\n");
		dbg(COMMAND_CHANNEL, "\n");
		dbg(COMMAND_CHANNEL, "\n");
		dbg(COMMAND_CHANNEL, "\n");
		dbg(COMMAND_CHANNEL, "Last fin timer Fired! wait 30 ms)\n");
		dbg (COMMAND_CHANNEL, "Sending FIN pack to node %hu (port %hhu)\n", nodeDest, nodeDestPort);

		// update socket State

		socketTuple = call Transport.getSocketArray(i);
		socketTuple.state = LAST_ACK;
		call Transport.updateSocketArray(i,&socketTuple);
		printSockets();

		dbg (COMMAND_CHANNEL, "Sending FIN packet\n");
		sendTCP (0b00100000, nodeDest, nodeDestPort, nodeSrcPort, call Random.rand32(), 0, NULL, 0);



		line();




		// send FIN packet to server (sort of a promise not to send any more data to server, but can still send ACKS and FIN's to server. But still mest be prepared to recieve data)
		//sendTCP (0b00100000, destination, srcPort, destPort, socketTuple.seq, socketTuple.ack, NULL, 0);

	}


	event void AMControl.startDone(error_t err){
		if(err == SUCCESS){
			dbg(GENERAL_CHANNEL, "Radio On\n");
		}else{
			//Retry until successful
			call AMControl.start();
		}
	}

	event void AMControl.stopDone(error_t err){}

	event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len){
		int i;
		uint8_t temp;
		uint32_t key;
		uint16_t copySrc;

		//bool found;
		//dbg(GENERAL_CHANNEL, "\nPacket Received: ");


		if(len==sizeof(pack)){
			pack* myMsg=(pack*) payload;
		//logPack (myMsg);	// just prints out package's info & payload
		if (myMsg->dest == TOS_NODE_ID) {

			//char text [] = "hi"; //"All neighbors, please reply";	// length is 27 (28 including null char byte '\0' at end) // Network Discovery message
			if (myMsg->TTL == 0 && myMsg->protocol == 6 && myMsg->src != TOS_NODE_ID) {	//&& strncmp(text, payload, 2) == 0) { // Should this also check if a network discovery packet has been sent recently???

				// record the neighbor (this packet's sender)
				// If this neighbor is not in neighborArray, then add it to neighborArray
				//found = FALSE;
				for (i = 0; i < top; i++) {
					if (neighbors[i] == myMsg->src) {
						break;
					}
				}
				if (i >= top) {	// code enters here if and only if the neighbor was not recorded.
					// record the neighbor (this packet's sender)
					neighbors [top] = myMsg->src;
					top++;
				}
				//neighbors [top] = myMsg->src;
				//top++;
				dbg (NEIGHBOR_CHANNEL, "Recieved my own network discovery packet from node %hhu. I now have %hhu neighbors\n", myMsg->src, top);

				return msg;
			} else {

				if (myMsg->protocol == PROTOCOL_PINGREPLY) {
					dbg (GENERAL_CHANNEL, "Recieved a reply to my message!\n");
					logPack (myMsg);
					return msg;
				}

				if (myMsg->protocol == PROTOCOL_PING) {
					dbg (COMMAND_CHANNEL, "The message is for me!\n");
					logPack (myMsg);
					logPack_command (myMsg);
					// send reply
					reply(myMsg->src);
				}

				if (myMsg->protocol == PROTOCOL_TCP) {// Handle TCP here
					line();
					dbg (COMMAND_CHANNEL, "The TCP message is for me!!!\n");
					//logPack (myMsg);
					logPack_command (myMsg);

					// check the payload flags to see if it's an SYN, SYN-ACK, ACK, FIN
					switch (myMsg->payload[0]) {
						bool portInitialized = FALSE;
						socket_store_t socketTuple;
						socket_store_t emptySocket;
						socket_t fd;
						socket_addr_t address;
						socket_addr_t * addr;
						uint8_t * buffPtr;
						int numUnacked;


						case 0b10000000:	// SYN Packet
							//dbg (COMMAND_CHANNEL, "Printing Payload in hex: 0x");
							//for (i = 0; i < PACKET_MAX_PAYLOAD_SIZE; i++) {
							//	printf ("%.2x", myMsg->payload[i]);
							//}
							//printf ("\n");
							dbg (COMMAND_CHANNEL, "Received a SYN Packet - flags: 0x%.2x, srcPort: %hhu, destPort: %hhu, TCPSeqNum: %u, ackNum: %u, transferSize: %hu\n", myMsg->payload[0], myMsg->payload[1], myMsg->payload[2], *((uint32_t *)(myMsg->payload + 3)), *((uint32_t *)(myMsg->payload + 7)), *((uint16_t *)(myMsg->payload + 11)));
							//data[1] == srcPort;
							//data[2] == destPort;

							//check if destPort has already been initialized by the server
							//portInitialized = FALSE;

							nodeDest = myMsg->src;
							nodeSrcPort = myMsg->payload[1];
							nodeDestPort = myMsg->payload[2];

							dbg(COMMAND_CHANNEL, "Initialized Ports: %hhu\n", topPort);

							for(i = 0; i < topPort; i++)
							{
								//dbg (COMMAND_CHANNEL, "Port %hhu = Port %hhu\n", initializedPorts[i], myMsg->payload[2]);
								if(initializedPorts[i] == myMsg->payload[2])
									portInitialized = TRUE;
							}

							if(portInitialized == TRUE)
							{
								line();
								printSockets();
								dbg (TRANSPORT_CHANNEL, "Node %hu receives | (SYN, seq=%u) from Node %hu\n", TOS_NODE_ID, *((uint32_t *)(myMsg->payload + 3)), myMsg->src);

								// setup socket in socketArray
								 fd = 0;
								address.port = myMsg->payload[2];
								address.addr = myMsg->src;
								addr = & address;


								if(call Transport.connect(fd,  addr) == SUCCESS)
								{
									dbg(COMMAND_CHANNEL, "\n");
									line();
									dbg(COMMAND_CHANNEL, "I, the server, got a connection from the client side socket\n");
									line();
									dbg(COMMAND_CHANNEL, "\n");

									// find empty socket and fill in with right values for new connection
									for(i = 0; i < 100; i++)
									{
										socketTuple = call Transport.getSocketArray(i);
										if(socketTuple.fd == 255){
											socketTuple.fd = i;

											socketTuple.srcAddr = TOS_NODE_ID;
											socketTuple.src = myMsg->payload[2];
											socketTuple.isSender = FALSE;
											socketTuple.dest.addr = myMsg->src;
											socketTuple.dest.port = myMsg->payload[1];
											socketTuple.numBytesRcvd = 0;
											socketTuple.sndWndSize = 27;	// 27 bytes (3 packets) can be sent without receiving an ACK
											dbg(COMMAND_CHANNEL, "Found empty socket! Socket #: %hhu\n", socketTuple.fd);
											socketTuple.state = SYN_RCVD;
											call Transport.updateSocketArray(i,&socketTuple);

											// Store the fd in a hashmap so it can be easily accessed later
											dbg (COMMAND_CHANNEL, "Storing file descriptor %hhu in hashmap by srcPort %hhu, destPort%hhu, and destAddress %hhu\n", socketTuple.fd, myMsg->payload[1], myMsg->payload[2], myMsg->src);
											call socketHashMap.insert ((myMsg->payload[1] << 24)|(myMsg->payload[2] << 16)|(myMsg->src), socketTuple.fd);

											printSockets();


											break;
										}

									}

								}

								// update seq and ack numbers in socket
								i = call socketHashMap.get(((myMsg->payload[2]) << 24)|((myMsg->payload[1]) << 16)| myMsg->src);
								socketTuple = call Transport.getSocketArray(i);

								// if the seq received is the same as the ack expected, we have received the right packet, update and send new ack
								if(socketTuple.ack == *((uint32_t *)(myMsg->payload + 3))){
									socketTuple.ack = *((uint32_t *)(myMsg->payload + 7)) + 1;
									call Transport.updateSocketArray(i,&socketTuple);
									dbg (TRANSPORT_CHANNEL, "Node %hu sends | (SYN+ACK, seq=0, ack=%u)\n", TOS_NODE_ID, socketTuple.ack);
									sendTCP (0b11000000, myMsg->src, myMsg->payload[2], myMsg->payload[1], socketTuple.seq, socketTuple.ack, NULL, 0);

									//update seq
									socketTuple.seq += 1;
									call Transport.updateSocketArray(i,&socketTuple);
								}






							}

							break;





							case 0b01000001:	// ACK Packet for three way handshake and close
							line();
								dbg(COMMAND_CHANNEL, "recieved the single ACK, do not reply\n");

								i = call socketHashMap.get(((myMsg->payload[2]) << 24)|((myMsg->payload[1]) << 16)| myMsg->src);
								socketTuple = call Transport.getSocketArray(i);

								// check if it's 3 way handshake ACK, or closing Ack
								if(socketTuple.state == ESTABLISHED) {
									socketTuple.state = CLOSE_WAIT;

								} else if(socketTuple.state == FIN_WAIT_1) {
										socketTuple.state = FIN_WAIT_2;

								} else if(socketTuple.state == FIN_WAIT_2) {
												socketTuple.state = TIME_WAIT;

								} else if(socketTuple.state == LAST_ACK) {
									socketTuple.state = CLOSED;
								} else if(socketTuple.state == SYN_RCVD){
									socketTuple.RTT = *((uint32_t *)(myMsg->payload + 11));
								} else {
									socketTuple.state = ESTABLISHED;
								}

								call Transport.updateSocketArray(i,&socketTuple);

								if(socketTuple.state == CLOSED)
								dbg(COMMAND_CHANNEL, "SERVER CONNECTION CLOSED\n");
								printSockets();
								line();
								break;



	//------------------------------------------------------------------------------------------------------------------------------------------------------


						case 0b01000000:	// ACK Packet
						  i = call socketHashMap.get(((myMsg->payload[2]) << 24)|((myMsg->payload[1]) << 16)| myMsg->src);
						  socketTuple = call Transport.getSocketArray(i);
							/*socketTuple.lastAck = *((uint32_t *)(&(myMsg->payload[3])) + 1);*/
							//socketTuple.seq = *((uint32_t *)(myMsg->payload + 7)) + 1;
							call Transport.updateSocketArray(socketTuple.fd, &socketTuple);

							//dbg (TRANSPORT_CHANNEL, "Received an ack from Node %hu  |  (Data: %hhu, seq=%u, ack=%u)\n", myMsg->src, *((uint8_t *)(myMsg->payload + 11)),*((uint32_t *)(myMsg->payload + 3)), *((uint8_t *)(myMsg->payload + 7)));

							dbg (TRANSPORT_CHANNEL, "Received an ack from Node %hu, AdvertisedWindow = %hhu at time: %u\n", myMsg->src, *((uint8_t *)(myMsg->payload + 11)), call clientTimer.getNow());
							if (socketTuple.isSender){
								//dbg (TRANSPORT_CHANNEL, "I'm the sender. Continuing TCP stream:\n");

								// if get the ack before timeout

								/*dbg(TRANSPORT_CHANNEL, "received ack at time: %u\n", call clientTimer.getNow());
								dbg (TRANSPORT_CHANNEL, "bytes acked: %hhu\n", socketTuple.numberOfBytesSentAndAcked);
								dbg (TRANSPORT_CHANNEL, "last sent: %hhu\n", socketTuple.lastSent);
								dbg(TRANSPORT_CHANNEL,"Last successfully sent seq: %u\n", socketTuple.lastSuccessfulSeq);
								dbg (TRANSPORT_CHANNEL, "lowestUnackedSentByte: %u\n", socketTuple.lowestUnackedSentByte);
								dbg (TRANSPORT_CHANNEL, "timeOut[0]: %u\n", socketTuple.timeOut[0]);*/



								dbg(TRANSPORT_CHANNEL, "UNACKED PACKETS [ index: %u, ack: %u, timeOut: %u ]\n", (call ackQ.element(0)).index, (call ackQ.element(0)).ack, (call ackQ.element(0)).timeOut);
								dbg(TRANSPORT_CHANNEL, "UNACKED PACKETS [ index: %u, ack: %u, timeOut: %u ]\n", (call ackQ.element(1)).index, (call ackQ.element(1)).ack, (call ackQ.element(1)).timeOut);
								dbg(TRANSPORT_CHANNEL, "UNACKED PACKETS [ index: %u, ack: %u, timeOut: %u ]\n", (call ackQ.element(2)).index, (call ackQ.element(2)).ack, (call ackQ.element(2)).timeOut);
								dbg(TRANSPORT_CHANNEL, "UNACKED PACKETS [ index: %u, ack: %u, timeOut: %u ]\n", (call ackQ.element(3)).index, (call ackQ.element(3)).ack, (call ackQ.element(3)).timeOut);
								dbg(TRANSPORT_CHANNEL, "UNACKED PACKETS [ index: %u, ack: %u, timeOut: %u ]\n", (call ackQ.element(4)).index, (call ackQ.element(4)).ack, (call ackQ.element(4)).timeOut);


								/*dbg(TRANSPORT_CHANNEL, "UNACKED PACKETS:\n")
								for(i = 0; i < socketTuple.transfer; i++)
								{
									dbg(TRANSPORT_CHANNEL, "")
								}*/


								if(call clientTimer.getNow() <= (call ackQ.element(0)).timeOut)
								{

									socketTuple.theirAdvertisedWindow = *((uint8_t *)(myMsg->payload + 11));

									/*numUnacked = 0;

									// check if its time to continueTCPStream
									for( i = 0; i < call ackQ.size(); i++){
										numUnacked++;
									}*/
									/*dbg (TRANSPORT_CHANNEL, "numUnacked Packs = %hhu, (numberOfBytesSent(%hhu) - numberOfBytesSentAndAcked(%hhu))/9 = %hhu\n", numUnacked, socketTuple.numberOfBytesSent, socketTuple.numberOfBytesSentAndAcked, (socketTuple.numberOfBytesSent - socketTuple.numberOfBytesSentAndAcked)/9 );
									if(numUnacked == socketTuple.sndWndSize)
										continueTCPStream(socketTuple);*/

									// ACK SUCCESSFULLY RECEIVED ON TIME, DEQUEUE
								//	socketTuple.lastAck++;
									//socketTuple.seq += (call ackQ.element(0)).bytes;
									//socketTuple.lastSent += (call ackQ.element(0)).bytes;
									dbg(CLEAN_OUTPUT,"numberOfBytesSentAndAcked = %hhu, bytes = %d\n", socketTuple.numberOfBytesSentAndAcked,(call ackQ.element(0)).bytes);
									socketTuple.numberOfBytesSentAndAcked += (call ackQ.element(0)).bytes;
									dbg(CLEAN_OUTPUT, " numberOfBytesSentAndAcked = %hhu\n", socketTuple.numberOfBytesSentAndAcked);
									/*dbg(CLEAN_OUTPUT,"numberOfBytesSentAndAcked = %hhu, bytes = ", socketTuple.numberOfBytesSentAndAcked,(call ackQ.element(0)).bytes);*/
									call ackQ.dequeue();
									call Transport.updateSocketArray(socketTuple.fd, &socketTuple);




									continueTCPStream(socketTuple);




								dbg (TRANSPORT_CHANNEL, "Received an ack from Node %hu  |  (Data: %hhu, seq=%u, ack=%u)\n", myMsg->src, *((uint8_t *)(myMsg->payload + 11)),*((uint32_t *)(myMsg->payload + 3)), *((uint8_t *)(myMsg->payload + 7)));
									//dbg (CLEAN_OUTPUT, "Received an ack from Node %hu  |  (Data: %hhu, seq=%u, ack=%u)\n", myMsg->src, *((uint8_t *)(myMsg->payload + 11)),*((uint32_t *)(myMsg->payload + 3)), *((uint8_t *)(myMsg->payload + 7)));

									//dbg (CLEAN_OUTPUT, "Received Data: %hhu\n", *((uint8_t *)(myMsg->payload + 11)));


								}
								else {

											// resend the packet
											/*buffPtr = &socketTuple.sendBuff[socketTuple.lastSent];
											sendTCP (0b00010000, socketTuple.dest.addr, socketTuple.src, socketTuple.dest.port, socketTuple.seq, socketTuple.ack, buffPtr, 1);*/

								}
								/*else // resend the packet, from sendBuff[0]
								{
									// update timeout
									dbg(TRANSPORT_CHANNEL, "---------------------------------------------------------------------\n");
									dbg(TRANSPORT_CHANNEL, "LATE PACKET! RESENDING\n");
									dbg(TRANSPORT_CHANNEL, "---------------------------------------------------------------------\n");
									rcvd_ack_time = call clientTimer.getNow() + socketTuple.RTT;
									buffPtr = &socketTuple.sendBuff[0];
									dbg (TRANSPORT_CHANNEL, "Node %hu resends | (Data: %hhu, seq=%u, ack=%u)\n", TOS_NODE_ID, *buffPtr, socketTuple.seq, socketTuple.ack);
									sendTCP (0b00010000, socketTuple.dest.addr, socketTuple.src, socketTuple.dest.port, socketTuple.seq, socketTuple.ack, buffPtr, 1);

								}*/

							}
							break;





						case 0b11000000:	// SYN-ACK Packet

							//endTime = call clientTimer.getNow();
							//dbg (COMMAND_CHANNEL, "End time is: %hhu\n", endTime );
							//rtt_calc = endTime - startTime;
							//dbg (COMMAND_CHANNEL, "RTT is: %hhu\n", rtt_calc );

							key = call clientTimer.getNow();
							dbg (COMMAND_CHANNEL, "End time is: %u\n", key );

							// find empty socket and fill in with right values for new connection
							i = call socketHashMap.get(((myMsg->payload[2]) << 24)|((myMsg->payload[1]) << 16)| myMsg->src);
							socketTuple = call Transport.getSocketArray(i);

							//rtt_calc = endTime - startTime;
							socketTuple.RTT = key - socketTuple.RTT;

							dbg (COMMAND_CHANNEL, "RTT is: %u\n", socketTuple.RTT );
							line();
							// setup socket in socketArray
							fd = 0;
							address.port = myMsg->payload[2];
							address.addr = myMsg->src;
							addr = &address;


							//if(call Transport.connect(fd,  addr) == SUCCESS)
							//{
								dbg(COMMAND_CHANNEL, "\n");
								line();
								dbg(COMMAND_CHANNEL, "I, the client, made a connection on the server side socket\n");
								line();
								dbg(COMMAND_CHANNEL, "\n");

								//socketTuple = call Transport.getSocketArray(socketHashMap.get(((myMsg->payload[2]) << 24)|((myMsg->payload[1]) << 16)| myMsg->src);
								//socketTuple.srcAddr = TOS_NODE_ID;
								//socketTuple.src = myMsg->payload[2];

								//socketTuple.dest.addr = myMsg->src;
								//socketTuple.dest.port = myMsg->payload[1];

								// read the effective window from the SYN-ACK Packet, and store it in socketTuple:
								//socketTuple.effectiveWindow = 50;
								//socketTuple.lastSent = 0;	// was already set to 0


								//socketTuple.RTT = rtt_calc;
								socketTuple.state = ESTABLISHED;


								dbg(COMMAND_CHANNEL, "Found my connection's socket! Socket #: %hhu\n", socketTuple.fd);
								//call Transport.updateSocketArray(i,&socketTuple);



						// update seq and ack numbers in socket
						//i = call socketHashMap.get(((myMsg->payload[2]) << 24)|((myMsg->payload[1]) << 16)| myMsg->src);
						//socketTuple = call Transport.getSocketArray(i);
						// ack = seq + 1
						socketTuple.ack = *((uint32_t *)(myMsg->payload + 3)) + 1;
						socketTuple.seq += 1;

						// save the ack as last acked!
						socketTuple.lastAck = *((uint32_t *)(myMsg->payload + 7));

						call Transport.updateSocketArray(i,&socketTuple);

							dbg (TRANSPORT_CHANNEL, "Node %hu receives | SYN+ACK\n", TOS_NODE_ID);


							dbg (TRANSPORT_CHANNEL, "Node %hu sends | (ACK, seq=%u, ack=%u)\n", TOS_NODE_ID, socketTuple.seq, socketTuple.ack);






							printSockets();


							dbg (COMMAND_CHANNEL, "Sending ACK packet from |Node: %hhu port %hhu| ---> |Node: %hhu port %hhu| \n", TOS_NODE_ID, myMsg->payload[2], myMsg->src, myMsg->payload[1]);
							sendTCP (0b01000001, myMsg->src, myMsg->payload[2], myMsg->payload[1], call Random.rand32(), myMsg->seq + 1, (uint8_t *)&(socketTuple.RTT), sizeof(socketTuple.RTT));

							// Begin sending data
							if (socketTuple.isSender){
								dbg (COMMAND_CHANNEL, "I'm the sender. Continuing TCP stream:\n");
								continueTCPStream(socketTuple);
							}


							break;

						case 0b00100000:	// FIN Packet
							dbg (COMMAND_CHANNEL, "Received a FIN packet\n");
							i = call socketHashMap.get(((myMsg->payload[2]) << 24)|((myMsg->payload[1]) << 16)| myMsg->src);
							socketTuple = call Transport.getSocketArray(i);


							dbg(COMMAND_CHANNEL,"STATE: %d\n", socketTuple.state);
							printSockets();
							// if second fin packet

							if(socketTuple.state == FIN_WAIT_2)
							{
								socketTuple.state = TIME_WAIT;
								call Transport.updateSocketArray(i,&socketTuple);
								printSockets();
							}

							if(socketTuple.state == TIME_WAIT)
								{
									// send ACK and close connection
									dbg (COMMAND_CHANNEL, "CLIENT CONNECTION CLOSED\n");
									socketTuple.state = CLOSED;

									call Transport.updateSocketArray(i,&socketTuple);
									// socket is now closed
									printSockets();
									sendTCP (0b01000001, myMsg->src, myMsg->payload[2], myMsg->payload[1], call Random.rand32(), myMsg->seq + 1, NULL, 0);

								}

							else // if first fin packet
							{
								// update to CLOSE_WAIT
								socketTuple.state = CLOSE_WAIT;
								call Transport.updateSocketArray(i,&socketTuple);
								printSockets();

								dbg (COMMAND_CHANNEL, "Sending ACK packet\n");
								printSockets();
								sendTCP (0b01000001, myMsg->src, myMsg->payload[2], myMsg->payload[1], call Random.rand32(), myMsg->seq + 1, NULL, 0);

								// wait a bit and send fin also
								call lastFinTimer.startOneShot(30);


								// Remove connection from client and server's hashTables, and socketArrays
							}






							break;

	//------------------------------------------------------------------------------------------------------------------------------------------------------


						case 0b00010000:	// data
							/*dbg (TRANSPORT_CHANNEL, "Received a data packet from Node %hu  |  (Data: %s, seq=%u, ack=%u)\n", myMsg->src, (char *)(myMsg->payload + 11),*((uint32_t *)(myMsg->payload + 3)), *((uint8_t *)(myMsg->payload + 7)));*/
							dbg (TRANSPORT_CHANNEL, "Received a data packet from Node %hu  |  (Data: %hhu %hhu %hhu %hhu %hhu %hhu %hhu %hhu %hhu, seq=%u, ack=%u)\n", myMsg->src, myMsg->payload[11], myMsg->payload[12], myMsg->payload[13], myMsg->payload[14], myMsg->payload[15], myMsg->payload[16], myMsg->payload[17], myMsg->payload[18], myMsg->payload[19], *((uint32_t *)(myMsg->payload + 3)), *((uint8_t *)(myMsg->payload + 7)));

							// clean output
							dbg (CLEAN_OUTPUT, "Received Data: %hhu, %hhu, %hhu, %hhu, %hhu, %hhu, %hhu, %hhu, %hhu,\n", myMsg->payload[11], myMsg->payload[12], myMsg->payload[13], myMsg->payload[14], myMsg->payload[15], myMsg->payload[16],myMsg->payload[17],myMsg->payload[18],myMsg->payload[19]);

							// Find the socket fd using the socket Hash Map
							i = call socketHashMap.get(((myMsg->payload[2]) << 24)|((myMsg->payload[1]) << 16)| myMsg->src);
							socketTuple = call Transport.getSocketArray(i);


							// check if the seq you're receiving is the ack you expected, then you're receiving packet in the right order
							if(*((uint32_t *)(myMsg->payload + 3)) == socketTuple.ack)
							{

								// received the correct ACK! Now update the ack to (ACK + 1) since we're now expecting the next packets

								socketTuple.numBytesRcvd += 9;
								socketTuple.ack += 9;

								call Transport.updateSocketArray(fd, &socketTuple);



								// send an ACK
								/*dbg(TRANSPORT_CHANNEL, "Sending ack to Node %hu  |  (Data: %hhu, seq=%u, ack=%u)\n", myMsg->src, *((uint8_t *)(myMsg->payload + 11)), socketTuple.seq, socketTuple.ack);*/
								// temp is now this node's advertised window. The advertisedWindow of the current node.:
								temp = SOCKET_BUFFER_SIZE - ((socketTuple.ack - 1) - socketTuple.indLastByteReadFromRCVD);
								dbg (TRANSPORT_CHANNEL, "Sending ack to Node %hu AdvertisedWindow: %hhu |  (Data: %hhu %hhu %hhu %hhu %hhu %hhu %hhu %hhu %hhu, seq=%u, ack=%u)\n", myMsg->src, temp, myMsg->payload[11], myMsg->payload[12], myMsg->payload[13], myMsg->payload[14], myMsg->payload[15], myMsg->payload[16], myMsg->payload[17], myMsg->payload[18], myMsg->payload[19], socketTuple.seq, socketTuple.ack);
								sendTCP (0b01000000, socketTuple.dest.addr, socketTuple.src, socketTuple.dest.port, socketTuple.seq, socketTuple.ack, &temp, sizeof(temp));
							}


							break;


	//------------------------------------------------------------------------------------------------------------------------------------------------------

						default:		// data packet???
							dbg (COMMAND_CHANNEL, "Received a TCP Packet with unknown flags\n");
					}

				}

			}

		} else if (myMsg->TTL > 0 && myMsg->src != TOS_NODE_ID) {	// should also check that this packet wasn't already forwarded by this node (store a list of packets already forwarded in a hashmap or a list)
			myMsg->TTL --; // will decrementing TTL and incrementing seq this way work? Or do I have to make a new packet?

			// check if it's another node's network discovery packet
			if (myMsg->src == myMsg->dest) { // if source == destination, then it's a network discovery packet



				// If this neighbor is not in neighborArray, then add it to neighborArray

				for (i = 0; i < top; i++) {
					if (neighbors[i] == myMsg->src) {
						break;
					}
				}
				//dbg (NEIGHBOR_CHANNEL, "This line means that the new code is being added. i = %d. top = %hhu\n", i, top);
				if (i >= top) {
					// record the neighbor (this packet's sender)
					neighbors [top] = myMsg->src;
					top++;
					//dbg (NEIGHBOR_CHANNEL, "Top: %hhu\n", top);
				}

				/*neighbors [top] = myMsg->src;
				top++;*/

				dbg (NEIGHBOR_CHANNEL, "Recieved %hhu's neighbor discovery packet. Sending it back to them. I now have %hhu neighbors\n", myMsg->src, top);
				if (i >= top) {
					dbg (NEIGHBOR_CHANNEL, "Node %hhu is now discovered\n", myMsg->src);
				}

				copySrc = myMsg->src;

				myMsg->src = TOS_NODE_ID;	// set souce of network discovery packets to current node
				call Sender.send(*myMsg, myMsg->dest); // send it back to the sender
				sentPacks[packsSent%50] = ((myMsg->seq << 16) | myMsg->src); // keep track of all packs send so as not to send them twice
				packsSent++;

				return msg;
			}

			// check if packet has been sent by me before (in last 50 messages)

			key = ((myMsg->seq << 16) | myMsg->src); // lookup sentPacks by whether the pack's seq (number of packs made by the sender at the time) and src (the sender) match a previous packet sent
			for (i = 0; i < 50; i++) {
				if (key == sentPacks[i]) {
					break;
				}
			}
			if (i != 50) { // if i == 50, then that means it went through the entire array, and didn't find any match. So the packet must not have been sent before in last 50 forwards
				dbg(GENERAL_CHANNEL, "Recieved a packet I already sent. Dropping packet.\n");
				return msg;
			}

			// if it is a link state packet, then update forwarding table
			if (myMsg->protocol == PROTOCOL_LINKEDSTATE) {

				if (myMsg->src == TOS_NODE_ID) {
					dbg (ROUTING_CHANNEL, "Recieved my own LSP\n");
					dbg(ROUTING_CHANNEL, "Src: %hhu Dest: %hhu Seq: %hhu TTL: %hhu Protocol: %hhu	Payload:\n", myMsg->src, myMsg->dest, myMsg->seq, myMsg->TTL, myMsg->protocol);
					printLSP((uint8_t *)(myMsg->payload), ROUTING_CHANNEL);
					return msg;
				}



				//uint8_t * routingTableRow;
				//arr [PACKET_MAX_PAYLOAD_SIZE * 8];
				dbg (ROUTING_CHANNEL, "Recieved %hhu's linkState packet!!!\n", myMsg->src);
				dbg(ROUTING_CHANNEL, "Src: %hhu Dest: %hhu Seq: %hhu TTL: %hhu Protocol: %hhu	Payload:\n", myMsg->src, myMsg->dest, myMsg->seq, myMsg->TTL, myMsg->protocol);
				printLSP((uint8_t *)(myMsg->payload), ROUTING_CHANNEL);

				// copy the myMsg->src's neighbor list from payload to the myMsg->src's row in routingTableNeighborArray
				//readLinkStatePack (uint8_t * arrayTo, uint8_t * payloadFrom)
				readLinkStatePack (&(routingTableNeighborArray[myMsg->src - 1][0]), (uint8_t *)(myMsg->payload));
				routingTableNumNodes++;

				// Forward and keep flooding the Link State Packet
				call Sender.send(*myMsg, AM_BROADCAST_ADDR);
				sentPacks[packsSent%50] = ((myMsg->seq << 16) | myMsg->src); // keep track of all packs send so as not to send them twice
				packsSent++;
				//memccpy(routingTablerow, arr, PACKET_MAX_PAYLOAD_SIZE * 8);
				//return msg;
			} else {
				dbg (ROUTING_CHANNEL, "It's not for me. forwarding it on\n");
				call Sender.send(*myMsg, forwardingTableNext[myMsg->dest]);
			}



			//**************************************************************8
			// Should this store an array of last "top" (number of neighbors) amount of packets stored, to tell when one of them was sent back to previous node again????? That way packets won't go back and forth?????
			//call Sender.send(*myMsg, AM_BROADCAST_ADDR); // AM_BROADCAST_ADDR is only used for neighbor discovery and link state packets

			sentPacks[packsSent%50] = ((myMsg->seq << 16) | myMsg->src); // keep track of all packs send so as not to send them twice
			packsSent++;
		} else if (myMsg->TTL <= 0) {
			dbg (ROUTING_CHANNEL, "I recieved a packet with no more time to live. Dropping packet\n");
		} else if (myMsg->src == TOS_NODE_ID) {
			dbg (ROUTING_CHANNEL, "I recieved my own packet\n");
		}

			return msg;
		}
		dbg(ROUTING_CHANNEL, "Unknown Packet Type %d\n", len);



		return msg;
	}


	event void CommandHandler.ping(uint16_t destination, uint8_t *payload){
		dbg(GENERAL_CHANNEL, "\nPINGING:\t\t");
		makePack(&sendPackage, TOS_NODE_ID, destination, 21, PROTOCOL_PING, mySeqNum, payload, PACKET_MAX_PAYLOAD_SIZE);
		logPack(&sendPackage);	// just prints out package's info & payload
		//dbg(GENERAL_CHANNEL, "Pinging payload ", payload, " from ", TOS_NODE_ID, " to ", destination, "\n");
		dbg(GENERAL_CHANNEL, "\n");
		/*
		if (destination == TOS_NODE_ID) {
		dbg(GENERAL_CHANNEL, "Node " + str(TOS_NODE_ID) + "recieved a ping\n")
		} else {
		while (Time to live > 0) {
		call Sender.send(sendPackage, AM_BROADCAST_ADDR);
		sentPacks[packsSent%50] = ((sendPackage.seq << 16) | sendPackage.src);	// keep track of all packs send so as not to send them twice
		packsSent++;
		}

		}
		*/
		//call Sender.send(sendPackage, destination);
		//call Sender.send(sendPackage, AM_BROADCAST_ADDR); // AM_BROADCAST_ADDR is only used for neighbor discovery and Link State Packets
		call Sender.send(sendPackage, forwardingTableNext[destination]);

		printRoutingTable(COMMAND_CHANNEL);
		mySeqNum++;
		packsSent++;
	}

	event void CommandHandler.printNeighbors(){
		printNeighbors (COMMAND_CHANNEL);
	}

	event void CommandHandler.printRouteTable(){
		printRoutingTable(COMMAND_CHANNEL);
		//dbg(COMMAND_CHANNEL, "NUM NODES: %d\n", totalNumNodes);
		//printRoutingTable (COMMAND_CHANNEL);
		//dbg (COMMAND_CHANNEL, "Command Handler has printed routing table on command channel?\n");
	}

	event void CommandHandler.printLinkState(){
		uint8_t dummyLSP [PACKET_MAX_PAYLOAD_SIZE];
		dbg (ROUTING_CHANNEL, "Link State Packet:\n");
		writeLinkStatePack (dummyLSP);
		printLSP(dummyLSP, COMMAND_CHANNEL);
		dbg (COMMAND_CHANNEL, "Source: %hhu\n", TOS_NODE_ID);
		printNeighbors (COMMAND_CHANNEL);

	}

	event void CommandHandler.printDistanceVector(){}

	/*event void CommandHandler.setTestServer(uint16_t address, uint8_t port){*/
	event void CommandHandler.setTestServer(uint8_t port){

		int i;
		socket_addr_t ad;
		socket_addr_t * addr;
		socket_t fd;
		socket_store_t socketTuple;

		// change port to one from cmd
		ad.port = port;
		ad.addr = TOS_NODE_ID;

		addr = &ad;

		fd	= call Transport.socket();
		call Transport.bind(fd, addr);

		// function to check if client tries connections
		// accept()

		// add port to initialized ports array
		initializedPorts[topPort] = port;
		topPort++;

		socketTuple = call Transport.getSocketArray(fd);
		socketTuple.state = LISTEN;
		call Transport.updateSocketArray(fd, &socketTuple);


		/*dbg(COMMAND_CHANNEL, "Port: %hhu\n", port);

		dbg(COMMAND_CHANNEL, "Number of accepted ports: %hhu\n", topPort);
		dbg(COMMAND_CHANNEL, "port 0: %hhu\n", initializedPorts[0]);
		dbg(COMMAND_CHANNEL, "port 1: %hhu\n", initializedPorts[1]);
		dbg(COMMAND_CHANNEL, "port 2: %hhu\n", initializedPorts[2]);*/


		dbg(COMMAND_CHANNEL, "\n");



		// timer to attempt connections
		call serverTimer.startPeriodic(2000);





		/*socket_addr_t addr;
		socket_addr_t * ad;
		addr.port = 50;
		addr.addr = 1;

		ad = &addr;

		for(i = 0; i < 200; i++)
		{

			call Transport.bind(call Transport.socket(), ad);
		}*/


	}



	event void CommandHandler.setTestClient(uint16_t destination, uint8_t srcPort, uint8_t destPort, uint16_t transfer){

		int i;
		socket_addr_t ad;
		socket_addr_t * addr;
		socket_addr_t serverAddress;
		socket_t fd;
		socket_store_t socketTuple;
		uint32_t seq;
		uint32_t ack;
		char message [] = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ";
		/*nodeDest = destination;
		nodeSrcPort = srcPort;
		nodeDestPort = destPort;*/

		dbg (COMMAND_CHANNEL, "Destination: %hhu, srcPort: %hhu, destPort: %hhu, transfer: %hu\n", destination, srcPort, destPort, transfer);


		ad.port = srcPort;
		ad.addr = TOS_NODE_ID;

		addr = &ad;

		fd	= call Transport.socket();
		call Transport.bind(fd, addr);

		serverAddress.port = destPort;
		serverAddress.addr = destination;

		addr = &serverAddress;
		socketTuple = call Transport.getSocketArray(fd);
		socketTuple.srcAddr = TOS_NODE_ID;
		socketTuple.src = srcPort;
		socketTuple.dest.addr = destination;
		socketTuple.dest.port = destPort;
		socketTuple.isSender = TRUE;
		socketTuple.transfer = transfer;
		socketTuple.numberOfBytesSent = 0;
		socketTuple.numberOfBytesSentAndAcked  = 0;
		socketTuple.lastSent = 0;	// 0 bytes have been sent so far
		socketTuple.sndWndSize = 27;	// 27 bytes (3 packets) can be sent without receiving an ACK
		socketTuple.numBytesRcvd = 0;


		// allocate the buffer
		/*memcpy(&(socketTuple.sendBuff), message, transfer);
		socketTuple.sendBuff[transfer - 1] = '\0';*/
		for(i = 0; i < SOCKET_BUFFER_SIZE; i++){
			socketTuple.ackReceived[i] = 0;
		}

		for(i = 0; i < SOCKET_BUFFER_SIZE; i++){
			socketTuple.sendBuff[i] = i+1;
		}



		call Transport.updateSocketArray(fd, &socketTuple);

		// add port to initialized ports array
		initializedPorts[topPort] = srcPort;
		topPort++;



    // create random sequence number to start
		//seq = call Random.rand32();
		// set seq as 0 for now so debugging the seq's and ack's is easier
		seq = 0;

		// setup timer for calculating the RTT
		socketTuple.RTT = call clientTimer.getNow();

		dbg (COMMAND_CHANNEL, "Start time is: %u\n", socketTuple.RTT );

		// update socket State
		socketTuple.state = SYN_SENT;
		socketTuple.seq = 0;
		socketTuple.ack = 0;
		call Transport.updateSocketArray(fd, &socketTuple);

		printSockets();
		sendTCP (0b10000000, destination, srcPort, destPort, seq, 0, (uint16_t *)(&transfer), sizeof (transfer));	// SYN

		// add ((srcPort << 24)|(destPort << 16)|(destAddress)) to hashtable to look up file descriptor "fd" faster next time. "fd" will be used to look up the port in socketArray
		call socketHashMap.insert ((srcPort << 24)|(destPort << 16)|(destination), fd);


	}




	event void CommandHandler.setClientClose(uint16_t destination, uint8_t srcPort, uint8_t destPort){

		int i;
		//uint32_t seqNum;
		//uint32_t ackNum;
		socket_store_t socketTuple;




		i = call socketHashMap.get(((srcPort) << 24)|((destPort) << 16)| destination);


		// look up seq and ack number
		dbg(COMMAND_CHANNEL, "\n");
		dbg(COMMAND_CHANNEL, "\n");
		dbg(COMMAND_CHANNEL, "\n");
		dbg(COMMAND_CHANNEL, "\n");
		dbg(COMMAND_CHANNEL, "CLOSE (1/4)\n");

		dbg(COMMAND_CHANNEL, "Closing connection at Socket # %hhu\n", i);
		dbg (COMMAND_CHANNEL, "Closing connection from -> Destination: %hhu, srcPort: %hhu, destPort: %hhu\n", destination, srcPort, destPort);
		dbg (COMMAND_CHANNEL, "Sending FIN pack to node %hu (port %hhu)\n", destination, destPort);

		// update socket State

		socketTuple = call Transport.getSocketArray(i);
		socketTuple.state = FIN_WAIT_1;
		call Transport.updateSocketArray(i,&socketTuple);
		printSockets();
		line();




		// send FIN packet to server (sort of a promise not to send any more data to server, but can still send ACKS and FIN's to server. But still mest be prepared to recieve data)
		sendTCP (0b00100000, destination, srcPort, destPort, socketTuple.seq, socketTuple.ack, NULL, 0);


		// Wait to get ACK from server of this FIN


		// Wait for server to send it's last FIN (to know that the server is not sending more data)

	}



	/*event void CommandHandler.setAppServer(){}

	event void CommandHandler.setAppClient(){}*/

		event void CommandHandler.setAppServer(uint8_t port){
	 		//call setTestServer(port);
	 		// do other stuff with application???


			//-----------------------------------------------------------

			int i;
			socket_addr_t ad;
			socket_addr_t * addr;
			socket_t fd;
			socket_store_t socketTuple;

			dbg (CLEAN_OUTPUT, "Called setAppServer! port is: %hhu\n", port);


			// change port to one from cmd
			ad.port = port;
			ad.addr = TOS_NODE_ID;

			addr = &ad;

			fd	= call Transport.socket();
			call Transport.bind(fd, addr);

			// function to check if client tries connections
			// accept()

			// add port to initialized ports array
			initializedPorts[topPort] = port;
			topPort++;

			socketTuple = call Transport.getSocketArray(fd);
			socketTuple.state = LISTEN;
			call Transport.updateSocketArray(fd, &socketTuple);


			/*dbg(COMMAND_CHANNEL, "Port: %hhu\n", port);

			dbg(COMMAND_CHANNEL, "Number of accepted ports: %hhu\n", topPort);
			dbg(COMMAND_CHANNEL, "port 0: %hhu\n", initializedPorts[0]);
			dbg(COMMAND_CHANNEL, "port 1: %hhu\n", initializedPorts[1]);
			dbg(COMMAND_CHANNEL, "port 2: %hhu\n", initializedPorts[2]);*/


			dbg(COMMAND_CHANNEL, "\n");



			// timer to attempt connections
			call serverTimer.startPeriodic(2000);

	 	}

	 	event void CommandHandler.setAppClient(uint16_t destination, uint8_t srcPort, uint8_t destPort){
	 		dbg (CLEAN_OUTPUT, "Called setAppClient! destination: %hu, srcPort: %hhu, destPort: %hhu\n", destination, srcPort, destPort);


	 	}

	 	event void CommandHandler.appClientSend(uint16_t destination, uint8_t srcPort, uint8_t destPort, uint8_t * message){
	 		dbg (CLEAN_OUTPUT, "Called appClientSend! Message is: %s\n", (char *)message);




	 	}

	void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length){
		Package->src = src;
		Package->dest = dest;
		Package->TTL = TTL;
		Package->seq = seq;
		Package->protocol = protocol;
		memcpy(Package->payload, payload, length);
	}
}
