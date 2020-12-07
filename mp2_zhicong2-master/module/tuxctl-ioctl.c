/* tuxctl-ioctl.c
 *
 * Driver (skeleton) for the mp2 tuxcontrollers for ECE391 at UIUC.
 *
 * Mark Murphy 2006
 * Andrew Ofisher 2007
 * Steve Lumetta 12-13 Sep 2009
 * Puskar Naha 2013
 */

#include <asm/current.h>
#include <asm/uaccess.h>

#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/module.h>
#include <linux/fs.h>
#include <linux/sched.h>
#include <linux/file.h>
#include <linux/miscdevice.h>
#include <linux/kdev_t.h>
#include <linux/tty.h>
#include <linux/spinlock.h>

#include "tuxctl-ld.h"
#include "tuxctl-ioctl.h"
#include "mtcp.h"

#define debug(str, ...) \
	printk(KERN_DEBUG "%s: " str, __FUNCTION__, ##__VA_ARGS__)

/* local values */
#define bitmask_for_bioc 0xF
#define shift_four 4
#define shift_sixteen 16
#define shift_twentyfour 24
#define command_size 20
#define display_size 4
#define led_size 4
#define decimal_size 4
#define display_mask 0xF
#define display_shift 4
#define led_mask 0x1
#define led_shift 1
#define decimal_mask 0x1
#define decimal_shift 1
#define decimal_light 0x10
#define segment_size 6
#define segment_jmp 2
#define swap_1 0x20
#define swap_2 0x40
#define reset_1 0xDF
#define reset_2 0xBF
#define reset_led 0x0

int tux_init(struct tty_struct *tty);
int tux_buttons(struct tty_struct *tty, unsigned long arg);
int tux_set_led(struct tty_struct *tty, unsigned long arg);
int reset(struct tty_struct *tty);
int tux_led_ack(struct tty_struct *tty);
int tux_led_request(struct tty_struct *tty);
int tux_read_led(struct tty_struct *tty);

/* local variables */
/* 	0xE7 is the Hex representation of 0 on led
	0x06 is the Hex representation of 1 on led
	0xCB is the Hex representation of 2 on led
	0x8F is the Hex representation of 3 on led
	0x2E is the Hex representation of 4 on led
	0XAD is the Hex representation of 5 on led
	0XED is the Hex representation of 6 on led
	0X86 is the Hex representation of 7 on led
	0xEF is the Hex representation of 8 on led
	0xAE is the Hex representation of 9 on led
	0xEE is the Hex representation of A on led
	0x6D is the Hex representation of B on led
	0xE1 is the Hex representation of C on led
	0x4F is the Hex representation of D on led
	0xE9 is the Hex representation of E on led
	0xE8 is the Hex representation of F on led
 */
static unsigned char led_show[16] = {
	0xE7, 0x06, 0xCB, 0x8F,
	0x2E, 0xAD, 0xED, 0x86,
	0xEF, 0xAE, 0xEE, 0x6D,
	0xE1, 0x4F, 0xE9, 0xE8};
static spinlock_t tux_lock;
static unsigned int buttons_pressed;
static unsigned char command[command_size];
static unsigned char led_command[command_size];
static unsigned int track;
static int cmd_end;
static unsigned long last_led;
static int enable_flag;
static volatile unsigned char is_resetting;
static unsigned long flags;
/************************ Protocol Implementation *************************/

/*
 *   tux_init
 *   DESCRIPTION: to initialize the tux
 *   INPUTS: struct tty_struct *tty -- acts as a middle man between the serial port and the code
 *   OUTPUTS: none
 *   RETURN VALUE: 0 for success
 *   SIDE EFFECTS: tux board initialized
 */
int tux_init(struct tty_struct *tty)
{
	// spin_lock_init(&tux_lock);

	// spin_lock_irqsave(&tux_lock, flags);
	is_resetting = 0;	// initialize to 0
	buttons_pressed = 0; // initialize to 0
	enable_flag = 0;	 // initialize to 0
	track = 0;			 // initialize to 0
	last_led = reset_led;

	command[0] = MTCP_RESET_DEV; // put command into the first command
	command[1] = MTCP_LED_USR;   // put command into the second command
	command[2] = MTCP_BIOC_ON;   // put command into the third command
	cmd_end = 3;				 // it's 3 because there are 3 commands to put
	if (enable_flag == 0)		 // check if tux is being used
	{
		//printk("start to initialize\n");
		enable_flag = 1;						   // set flag to being used
		tuxctl_ldisc_put(tty, command + track, 1); // 1 because put the command 1 by 1
												   //printk("initialize succeeded!\n");
	}
	// spin_unlock_irqrestore(&tux_lock, flags);
	tux_set_led(tty, last_led);
	return 0;
}

/*
 *   tux_buttons
 *   DESCRIPTION: return buttons to user
 *   INPUTS: struct tty_struct *tty -- acts as a middle man between the serial port and the code
 * 		 	 unsigned long arg -- buttons to return
 *   OUTPUTS: none
 *   RETURN VALUE: 0 for success
 *   SIDE EFFECTS: buttons returned
 */
int tux_buttons(struct tty_struct *tty, unsigned long arg)
{
	int subsititue = 0; // initialize to 0
	int check1 = 0;		// initialize to 0
	int check2 = 0;		// initialize to 0
	spin_lock_irqsave(&tux_lock, flags);
	if (!arg)
	{
		return -EINVAL;
	}
	subsititue = buttons_pressed;
	check1 = subsititue & swap_1;
	check2 = subsititue & swap_2;
	subsititue = subsititue & reset_1;
	subsititue = subsititue & reset_2;
	subsititue = subsititue | (check1 << 1);
	subsititue = subsititue | (check2 >> 1);
	*((int *)arg) = subsititue;
	spin_unlock_irqrestore(&tux_lock, flags);

	return 0;
}

/*
 *   tux_set_led
 *   DESCRIPTION: set led
 *   INPUTS: struct tty_struct *tty -- acts as a middle man between the serial port and the code
 * 		 	 unsigned long arg -- things to be displayed
 *   OUTPUTS: none
 *   RETURN VALUE: 0 for success
 *   SIDE EFFECTS: led changed
 */
int tux_set_led(struct tty_struct *tty, unsigned long arg)
{
	bool check_led;
	bool check_decimal;
	char decimal_select;
	char led_select;
	long shifted_arg = arg;
	int j = 2; // counter to check the command total, it's 2 because the first 2 are MTCP_LED_SET and leds to be lightened
	int i;

	led_command[0] = MTCP_LED_SET;						// put the first command into led command
	led_select = (arg >> shift_sixteen) & display_mask; // check what led to be lighted
	//printk("led_select is %08x\n", led_select);
	led_command[1] = led_select; // put the second command into led command
	decimal_select = (arg >> shift_twentyfour) & display_mask;
	//printk("decimal_select is %08x\n", decimal_select);

	for (i = 0; i < led_size; i++)
	{
		check_led = led_select & led_mask;
		//printk("check_led %d is %08x\n", i, check_led);
		if (check_led)
		{
			led_command[j] = led_show[shifted_arg & display_mask];
			check_decimal = decimal_select & decimal_mask;
			//printk("check_decimal %d is %08x\n", i, check_decimal);
			if (check_decimal)
			{
				led_command[j] += decimal_light;
			}
			j++;
		}
		shifted_arg = shifted_arg >> display_shift;
		led_select = led_select >> led_shift;
		decimal_select = decimal_select >> decimal_shift;
	}

	// for (i = 0; i < j; i++) {
	// 	printk("led_command is %08x\n", led_command[i]);
	// }

	if (!enable_flag)
	{
		enable_flag = 1; // set the flag to being used
		last_led = arg;
		track = 0; // set track to 0 because have to execute command from the begining
		tuxctl_ldisc_put(tty, led_command, j);
	}

	return 0;
}

/*
 *   reset
 *   DESCRIPTION: function to handle reset packet
 *   INPUTS: struct tty_struct *tty -- acts as a middle man between the serial port and the code
 *   OUTPUTS: none
 *   RETURN VALUE: 0 for success
 * 				   -EINVAL for fail
 *   SIDE EFFECTS: reset all the things
 */
int reset(struct tty_struct *tty)
{
	if (!is_resetting)
	{
		// spin_lock_irqsave(&tux_lock, flags);
		command[0] = MTCP_RESET_DEV; // put the first command into command array
		track = 0;					 // set track to 0 because have to execute command from the begining
		cmd_end = 1;				 // it's 1 because only 1 command to execute
		enable_flag = 1;			 // set to being used mode
		is_resetting = 1;			 // set to 1 because it's the first package to send
		tuxctl_ldisc_put(tty, command + track, 1);

		buttons_pressed = 0; // reset buttons to not pressed
		enable_flag = 0;	 // reset flag to not being used state
		track = 0;			 // set track to 0 because have to execute command from the begining

		command[0] = MTCP_LED_USR; // put the first command into command array
		command[1] = MTCP_BIOC_ON; // put the second command into command array
		cmd_end = 2;			   // it's 2 because there are 2 command to execute
		if (enable_flag == 0)	  // check if it can be sent to tux
		{
			//printk("start to reset_initialize\n");
			enable_flag = 1; // set to being used mode
			tuxctl_ldisc_put(tty, command + track, 1);
			//printk("reset_initialize succeeded!\n");
		}
		// spin_unlock_irqrestore(&tux_lock, flags);
		tux_set_led(tty, last_led);
		return 0;
	}
	is_resetting = 0; // set back to 0 because the second package was received
	return 0;
}

/* tux_led_ack() */
int tux_led_ack(struct tty_struct *tty)
{
	spin_lock_irqsave(&tux_lock, flags);
	spin_unlock_irqrestore(&tux_lock, flags);
	return 0;
}

/* tux_led_request() */
int tux_led_request(struct tty_struct *tty)
{
	spin_lock_irqsave(&tux_lock, flags);
	spin_unlock_irqrestore(&tux_lock, flags);
	return 0;
}

/* tux_read_led */
int tux_read_led(struct tty_struct *tty)
{
	spin_lock_irqsave(&tux_lock, flags);
	spin_unlock_irqrestore(&tux_lock, flags);
	return 0;
}

/* tuxctl_handle_packet()
 * IMPORTANT : Read the header for tuxctl_ldisc_data_callback() in 
 * tuxctl-ld.c. It calls this function, so all warnings there apply 
 * here as well.
 */
void tuxctl_handle_packet(struct tty_struct *tty, unsigned char *packet)
{
	unsigned a, b, c;

	a = packet[0]; /* Avoid printk() sign extending the 8-bit */
	b = packet[1]; /* values when printing them. */
	c = packet[2];

	/*printk("packet : %x %x %x\n", a, b, c); */
	switch (a)
	{
	case MTCP_BIOC_EVENT:
		/* code */
		buttons_pressed = ((c & bitmask_for_bioc) << shift_four) + (b & bitmask_for_bioc);
		break;
	case MTCP_ACK:
		/* code */
		enable_flag = 0; // set flag back to not being used state
		track++;
		if (track != cmd_end)
		{
			enable_flag = 1;						   // set flag to being used state
			tuxctl_ldisc_put(tty, command + track, 1); // execute next command
		}
		break;
	case MTCP_RESET:
		/* code */
		reset(tty);
		break;
	default:
		break;
	}
}

/******** IMPORTANT NOTE: READ THIS BEFORE IMPLEMENTING THE IOCTLS ************
 *                                                                            *
 * The ioctls should not spend any time waiting for responses to the commands *
 * they send to the controller. The data is sent over the serial line at      *
 * 9600 BAUD. At this rate, a byte takes approximately 1 millisecond to       *
 * transmit; this means that there will be about 9 milliseconds between       *
 * the time you request that the low-level serial driver send the             *
 * 6-byte SET_LEDS packet and the time the 3-byte ACK packet finishes         *
 * arriving. This is far too long a time for a system call to take. The       *
 * ioctls should return immediately with success if their parameters are      *
 * valid.                                                                     *
 *                                                                            *
 ******************************************************************************/
int tuxctl_ioctl(struct tty_struct *tty, struct file *file,
				 unsigned cmd, unsigned long arg)
{
	switch (cmd)
	{
	case TUX_INIT:
		return tux_init(tty);
	case TUX_BUTTONS:
		return tux_buttons(tty, arg);
	case TUX_SET_LED:
		return tux_set_led(tty, arg);
	case TUX_LED_ACK:
		return tux_led_ack(tty);
	case TUX_LED_REQUEST:
		return tux_led_request(tty);
	case TUX_READ_LED:
		return tux_read_led(tty);
	default:
		return -EINVAL;
	}
}
