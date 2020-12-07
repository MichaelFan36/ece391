
# mp1.S - life-or-death version
# Good luck, and have fun!

.data

    # Constants for accessing the fields of a struct keystroke_args
    # struct keystroke_args is defined in rtc.h and mp1.h

	KA_SIZE	  = 14   # 14 bytes when copying
	KA_STACK  = 16   # use 16 bytes on stack for alignment
	DIRECTION = 0
	SELECTOR  = 2
	GUESS     = 4
	HINT      = 9

    # Constants for accessing the fields of a struct game_status
    # struct game_status is defined in rtc.h and mp1.h

	GS_SIZE   = 8	# 8 bytes
	POP 	  = 0
	INF	  = 4

    # Constants for screen size

    	SCR_WIDTH  = 80
	SCR_HEIGHT = 20
	SCR_SIZE   = ((SCR_WIDTH) * (SCR_HEIGHT))

    # ASCII cell images

        CELL_LIVE = 0x78
	CELL_DEAD = 0x20


# Data shared between this file and rtc.c helper functions

# This '.globl' directive makes these symbols visible externally
.globl rand_seed, aggression

			.align 8
rand_seed:		.quad 0x0	# Pseudo-random number seed
aggression:		.long 0x0	# Aggression level of virus


# Data private to this file

current_board:		.long 0x0	# Address of current board
next_board:		.long 0x0	# Address of next board
population:		.long 0x0	# Remaining human population
infection:		.long 0x0	# Count of live virus cells
select_image:		.string "==>"	# Picture of the selector
select_blank:		.string "   "	# Picture to overwrite selector
base_array:             .string "ACGT"  # Array of characters for bases

.text

# void mp1_poke(void);
# You can use this function to write to video memory.
#
# Interface: Register-based arguments (not C-style)
#    Inputs: %cl  - The byte you wish to write
#            %eax - Offset from the start of video memory that you wish
#                   to write to
#   Outputs: Text-mode video screen is written to at location %eax with
#            the byte in %cl
# Registers: Clobbers EDX

mp1_poke:
		movl    vmem_base_addr(,1),%edx
		movb    %cl,(%edx,%eax,1)
		ret

#   ----------------- Exported functions ---------------------

# void mp1_rtc_tasklet(unsigned long ignore);
# Performs three tasks:
#	(1) updates the life game board and calculates infection count
#	(2) swaps the two boards
#	(3) applies population reduction based on infection count
#	(4) redraws the screen
#	(5) notifies the user code by calling mp1_notify_user
# Inputs   : none
# Outputs  : none
# Registers: Standard C calling convention

.globl mp1_rtc_tasklet
mp1_rtc_tasklet:
		pushl %ebp
		movl %esp, %ebp
		pushl %ebx
		pushl %esi
		pushl %edi 									

		subl $16, %esp							
		xorl %ebx, %ebx              
		movl current_board, %esi
		cmp $0, %esi
		je tasklet_done							

		movl $0, (%esp)						# row pointer 
		movl $0, 4(%esp)						# column pointer
		movl $0, 8(%esp)						# live_cells pointer
		movl $0, 12(%esp)						# total cells pointer

	tasklet_loop:
	check_row:
		movl (%esp), %ebx						# put row pointer into ebx
		cmp $0, %ebx							# to see if it is the first row
		je on_bound
		cmp $19, %ebx							# to see if it is the last row
		je on_bound
	check_column:
		movl 4(%esp), %ebx						# put column pointer into ebx
		cmp $0, %ebx							# to see if it is the first column
		je on_bound
		cmp $79, %ebx							# to see if it is the last column
		je on_bound
	
		pushl %esi								# save esi since needed
		call neighbor_count
		popl %esi
		xorl %ebx, %ebx							# make sure the high 24 bits are 0
		movb (%esi), %bl						# bl contains the current cell value
		pushl %eax								# push parameterss
		pushl %ebx								
		call tick_result						# eax now contain
		popl %ebx
		popl %ebx								# pop out useless values

		movl next_board, %edi				
		movl 12(%esp), %ebx						# locate the cell in the next board
		cmp $0, %eax							# to see if the cell die or live
		je next_dead
		movb $1, %dl							# store alive
		jmp next_alive

	next_dead:
		movb $0, %dl							# store death
		movb %dl, (%edi, %ebx)					# put the cell to death
		jmp on_bound
	next_alive:
		movb %dl, (%edi, %ebx)					# put the cell to alive
		movl 8(%esp), %ebx						# add one living cell
		incl %ebx
		movl %ebx, 8(%esp)						# store living cell back to stack
	on_bound:
		incl %esi								# move to the next cell						
		movl 4(%esp), %ebx						# move to the next column		
		incl %ebx
		cmp $79, %ebx							# check if it is the last column
		ja tasklet_rejust							
		movl %ebx, 4(%esp)						# store it back column stack
		movl 12(%esp), %ebx						# add one more total number of cells
		incl %ebx
		movl %ebx, 12(%esp)						# store it back to total number of cells
		jmp tasklet_loop

	tasklet_rejust:
		movl $0, %ebx							# reset column to 0 first
		movl %ebx, 4(%esp)						# reset column stack to 0
		movl 12(%esp), %ebx						# add one more cell
		incl %ebx
		movl %ebx, 12(%esp)						# store total number of cells back to cells counter
		movl (%esp), %ebx						# add one more row
		incl %ebx
		movl %ebx, (%esp)
		cmp $19, %ebx							# to see if it is the last row
		ja before_finish							
		jmp tasklet_loop

	before_finish:										
		movl 8(%esp), %ebx						# see how many cells are alive in the next board
		imul $10, %ebx, %eax					# calculate 10 * living cells
		movl %eax, infection				 	# move infection number to infection
		movl current_board, %eax				# swap the boards
		movl next_board, %ebx
		movl %ebx, current_board
		movl %eax, next_board				

		movl population, %eax					# to see if population is smaller than infection
		cmp infection, %eax
		jbe no_people			

		subl infection, %eax					# decrease infection from population
		movl %eax, population						
		jmp tasklet_done
	no_people:
		movl $0, %ebx							# put 0 into population since population is smaller than infection
		movl %ebx, population
	tasklet_done:
		pushl %edx								
		call draw_screen						# draw the screen
		call mp1_notify_user					# notify
		popl %edx
		add $16, %esp							# pop out the useless value
		popl %edi
		popl %esi
		popl %ebx
		leave
		ret



# int mp1_ioctl(unsigned long arg, unsigned int cmd)
# The dispatch function for the MP1 ioctls - should use the cmd argument
# and a jumptable to execute one of the specific ioctls implemented below.
# Inputs   : unsigned long arg - parameter to the mp1_ioctl_....
#          : unsigned int cmd  - specifies which mp1_ioctl_... function
#          :                     to execute
# Outputs  : Returns an integer - depends on which ioctl() function is called
# Registers: Standard C calling convention

.globl mp1_ioctl
mp1_ioctl:
		movl 8(%esp), %eax				# put the comand operation into eax
		cmp $4,%eax						# to see if it is greater than 4
		ja fail_1
		cmp $0,%eax						# to see if it is smaller than 0
		jl fail_1
		# do I need to push long argument?
		jmp *jumptable(,%eax,4)			# jump to the corresponding function
	fail_1:
		movl $-1, %eax					# move fail value into eax 
		ret


# ----------------- Functions private to this file -------------------

# void mp1_draw_screen;
# Performs one task:
#	(1) draw every cell
# Inputs   : none
# Outputs  : screen
# Registers: Standard C calling convention
draw_screen:
	# For simplicity, your implementation may assume a SCR_WIDTH of 80.
		pushl %ebp
		movl %esp, %ebp
		pushl %ebx
		pushl %esi
		pushl %edi 									

		subl $12, %esp					# move up for 12 bytes(leaving space)
		xorl %ebx, %ebx					# initialize ebx for storing data							
		movl current_board, %edi 		# %edi will store address forever
	  	cmp $0, %edi					# to see if it can be drawn
		je draw_done									

		movl $0, (%esp)				# make row pointer to 0
		movl $0, 4(%esp)				# make column pointer to 0
		movl $0, 8(%esp)				# make total number cells to 0
	draw_loop:
		movl 8(%esp), %ebx				# total number of cells to ebx
		movb (%edi, %ebx), %cl			# to see if the cell is dead or alive
		cmp $1, %cl						# to see if it's alive
		je draw_alive									
		cmp $0, %cl						# to see if it's dead
		je draw_dead								
		jmp draw_bound					# jump if the cell is on the outer bound, beacuse didn't set bound to 0 or 1


	draw_alive:
		imul $2, %ebx, %eax				# calculate offset
		movb $CELL_LIVE, %cl
		pushl %edx
		call mp1_poke
		popl %edx
		jmp draw_continue
	draw_dead:
		imul $2, %ebx, %eax				# calculate offset
		movb $CELL_DEAD, %cl
		pushl %edx
		call mp1_poke
		popl %edx
		jmp draw_continue
	draw_bound:									
		imul $2, %ebx, %eax				# calculate offset
		movb $CELL_DEAD, %cl			# cells on the outer are all dead
		pushl %edx
		call mp1_poke
		popl %edx


	draw_continue:
		movl 4(%esp), %ebx				# calculate which column is it
		cmp $79, %ebx					# to see if it is the right most column
		je draw_rejust				
		incl %ebx						# move to the next column
		movl %ebx, 4(%esp)				# store it back to column stack
		movl 8(%esp), %ebx				# increase the total number of cells
		incl %ebx
		movl %ebx, 8(%esp)				# store it back to total number of cells
		jmp draw_loop

	draw_rejust:
		movl 8(%esp), %ebx				# increase the total number of cells
		incl %ebx
		movl %ebx, 8(%esp)				# store it back to total number of cells
		movl $0, %ebx				 	# move row to 0
		movl %ebx, 4(%esp)				# rejust row back to 0			
		movl (%esp), %ebx				# to see if it is the last column
		cmp $19, %ebx					# to see if it is the last row
		je draw_done
		incl %ebx						# increase one row
		movl %ebx, (%esp)
		jmp draw_loop

	draw_done:
		add $12, %esp					# pop out useless value
		popl %edi
		popl %esi
		popl %ebx
		leave
		ret

# void mp1_ioctl_startgame(unsigned long seed);
# Performs three tasks:
#	(1) randomly generate seed
#	(2) malloc space for current board and next board
#	(3) initialize game
#	(4) set 80 to aggression
#	(5) set 8000000 to population
# Inputs   : unsigned long seed
# Outputs  : 0 for success, -1 for failure
# Registers: Standard C calling convention
mp1_ioctl_startgame:
		pushl %ebp
		movl %esp, %ebp
		pushl %ebx
		pushl %esi
		pushl %edi

	gen_seed:
		movl 8(%ebp), %ebx					# put parameter for seed_generator		
		pushl %edx							# save the value of edx for caller convention
		pushl %ebx
		call seed_generator					# ecx will change!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
		popl %ebx
		popl %edx
	first_call_malloc:
		movl $SCR_SIZE, %ebx				
		pushl %edx							# save the value of edx for caller convention
		pushl %ebx							# push parameter for malloc
		call mp1_malloc							
		popl %ebx
		popl %edx
		cmp $0, %eax						# check if malloc fails								
		je start_fail1
		movl %eax, current_board			# now current_board points to the new address
	second_call_malloc:
		pushl %edx
		pushl %ebx
		call mp1_malloc							
		popl %ebx
		popl %edx
		cmp $0, %eax						# check if malloc fails	
		je start_fail2
		movl %eax, next_board				# now the next_board points to the new address


		movl current_board, %esi			# initialize setup
		movl next_board, %edi				
		movl $0, %ecx						# counter setup			

	startgame_loop:
		movb $0, %bl						# store it to 0
		movb %bl, (%ecx, %esi)				# set all current board to 0
		movb %bl, (%ecx, %edi)				# set all next board to 0
		cmp $SCR_SIZE, %ecx
		jae startgame_loop2			
		incl %ecx
		jmp startgame_loop

	startgame_loop2:
		movl current_board, %esi			# have to reload, because board changes
		pushl %edx							# save the value for edx
		pushl %esi
		call init_virus
		popl %esi
		popl %edx
		movl %eax, infection					
		movl $80, %eax						# initialize aggression to 80
		movl %eax, aggression
		movl $8000000, %eax					# initialize population to 8000000
		movl %eax, population
		popl %esi
		popl %eax
		popl %edi
		popl %edx
		popl %ecx
		movl $0, %eax						# return success	
		leave
		ret


	start_fail1:
		movl $0, %ebx						# clear ebx
		movl %ebx, current_board
		movl %ebx, next_board				
		popl %esi
		popl %eax
		popl %edi
		popl %edx
		popl %ecx
		movl $-1, %eax						# return failure				
		leave
		ret

	start_fail2:
		movl current_board, %ebx
		pushl %edx
		pushl %ebx
		call mp1_free
		popl %ebx
		popl %edx										
		movl $0, %ebx						# clear ebx
		movl %ebx, current_board
		movl %ebx, next_board				
		popl %esi
		popl %eax
		popl %edi
		popl %edx
		popl %ecx
		movl $-1, %eax						# return failure			
		leave
		ret

# void mp1_ioctl_endgame(unsigned long ignore);
# Performs three tasks:
#	(1) called when the game is over
# Inputs   : unsigned long ignore
# Outputs  : none
# Registers: Standard C calling convention

mp1_ioctl_endgame:
		pushl %ebp									# initialize setup
		movl %esp, %ebp
		pushl %ebx
		pushl %esi
		pushl %edi

		movl current_board, %esi						# free current board
		push %esi
		call mp1_free
		popl %esi
		movl $0, %ebx							# clear ebx
		movl %ebx, current_board				# set current board pointer to 0

		movl next_board, %esi						# free current board
		push %esi
		call mp1_free
		popl %esi
		movl $0, %ebx						# clear ebx
		movl %ebx, next_board				# set current board pointer to 0
	end_done:
		popl %edi
		popl %esi
		popl %ebx
		movl $0, %eax						# return success
		leave
		ret
# void mp1_ioctl_keystroke(struct keystroke_args* keystroke_args);
# Performs three tasks:
#	(1) up
#	(2) down
#	(3) left
#	(4) right
# Inputs   : struct keystroke_args* keystroke_args
# Outputs  : -1 for failure, 0 for success
# Registers: Standard C calling convention
mp1_ioctl_keystroke:
		pushl %ebp
		movl %esp, %ebp
		pushl %ebx
		pushl %esi
		pushl %edi

		subl $KA_STACK, %esp			# make space for call from user
		movl %esp, %esi				# store the address of pointer
		movl $KA_SIZE, %eax
		movl 8(%ebp), %ebx
		cmp $0, %ebx
		je keystroke_fail1

		pushl %eax					# push parameter
		pushl 8(%ebp)				# push parameter
		pushl %esi					# push parameter
		call mp1_copy_from_user
		cmp $0, %eax				# check if copy fail
		jne keystroke_fail1
		popl %esi
		xorl %edx, %edx
		movw (%esi), %dx			# check which operation it is
		popl %ebx
		popl %ebx

		xorl %edi, %edi
		cmp $0, %dx				# see if it is left
		je left_right
		cmp $1, %dx				# see if it is down
		je up_down
		cmp $2, %dx				# see if it is right
		je left_right
		cmp $3, %dx				# see if it is up
		je up_down

	left_right:
		cmp $3, %edi				# loop to erase the original selector
		je left_right_go
		xorl %ebx, %ebx
		movw 2(%esi), %bx
		xorl %eax, %eax				# make sure nothing is in the high bits			
		imul $10, %bx, %ax			# calculate the offset of this selector
		addl $1774, %eax		# add the fixede value for selector
		addl %edi,%eax				# move to the next place
		imul $2, %eax				# times 2 because 2 bytes?
		movb select_blank(%edi), %cl	# move the first char of blank to cl
		pushl %edx
		call mp1_poke		
		popl %edx		
		incl %edi
		jmp left_right

	left_right_go:	
		xorl %edi, %edi				# reset counter to 0
		movw 2(%esi), %ax			
		cmp $0, %dx				# to see it's left or right
		je left
		cmp $4, %ax				# to see if the current selector is the right most one
		je right_most
		incw %ax
		jmp left_right_continue
	left:
		cmp $0, %ax				# to see if the current selector is the left most one
		je left_most				 
		decw %ax					# if not, decrease by 1
	
	left_right_continue:
		movw %ax, 2(%esi)			# rewrite it back to user
	left_right_loop:
		cmp $3, %edi
		je keystroke_done
		xorl %ebx, %ebx
		movw 2(%esi), %bx			# read the new selector
		xorl %eax, %eax				# make sure nothing is in the high bits	
		imul $10, %bx, %ax			# calculate the new offset
		addl $1774, %eax		# add the fixede value for selector
		addl %edi,%eax				# move to the next place
		imul $2, %eax				# times 2 because 2 bytes?
		movb select_image(%edi), %cl
		pushl %edx
		call mp1_poke
		popl %edx
		incl %edi
		jmp left_right_loop

	left_most:
		movw $4, %ax		   # set the selector to the right most one
		jmp left_right_continue
	right_most:
		movw $0, %ax			# set the selector to the left most one
		jmp left_right_continue



	up_down:
		xorl %eax, %eax			# clear eax for later use
		movw 2(%esi), %ax		# check which cell does it select

	up_down_choose:
		movb 4(%eax, %esi), %bl	# move to the chosen guess
		cmp $1, %dx				# to check if it is up or down
		je down
		movb $1, %cl				# if it's up move 0001 to cl
		jmp up_down_go				
	down:
		movb $8, %cl				# if it's up move 1000 to cl
	up_down_go:
		cmp $0, %bl				# determine how to rotate cl
		je up_down_rotate_cell_0
		cmp $1, %bl
		je up_down_rotate_cell_1
		cmp $2, %bl
		je up_down_rotate_cell_2
		cmp $3, %bl
		je up_down_rotate_cell_3


	up_down_continue:				# start to compare with hint
		movb 9(%eax, %esi), %bl		# put corresponding hint into bl
		andb %cl, %bl				# to see if guess is in hint
		cmp $0, %bl
		jne up_down_done				# it's in then done
		cmp $1, %dx				# to see if it's down
		je down_compare
		cmp $8, %cl				# to see if it reaches the left most
		je up_rejust	
		shlb $1, %cl
		jmp up_down_continue

	up_rejust:						# rejust it to 0001
		movb $1, %cl
		jmp up_down_continue

	down_compare:					# to see if it reaches the right most
		cmp $1, %cl
		je down_rejust
		shrb $1, %cl
		jmp up_down_continue
	
	down_rejust:					# rejust it to 1000
		movb $8, %cl
		jmp up_down_continue



	up_down_rotate_cell_0:			# The current guess is A
		cmp $1, %dx
		je rotate_down_0
		shlb $1, %cl				# if it's up it goes to C, so need change to 0010
		jmp up_down_continue
	rotate_down_0:					# if it's down it goes to T, so no need change to 1000
		jmp up_down_continue

	up_down_rotate_cell_1:			# The current guess is C
		cmp $1, %dx
		je rotate_down_1
		shlb $2, %cl				# if it's up it goes to G, so need change to 0100
		jmp up_down_continue
	rotate_down_1:
		shrb $3, %cl
		jmp up_down_continue		# if it's down it goes to A, so need change to 0001

	up_down_rotate_cell_2:			# The current guess is G
		cmp $1, %dx
		je rotate_down_2
		shlb $3, %cl				# if it's up it goes to T, so need change to 1000
		jmp up_down_continue
	rotate_down_2:
		shrb $2, %cl				# if it's down it goes to C, so need change to 0010
		jmp up_down_continue		

	up_down_rotate_cell_3:			# The current guess is T
		cmp $1, %dx
		je rotate_down_2			# if it's up it goes to A, so no need change to 0001
		jmp up_down_continue
	rotate_down_3:
		shrb $1, %cl				# if it's down it goes to G, so need change to 0100
		jmp up_down_continue




	up_down_done:
		xorl %ebx, %ebx
		movw 2(%esi), %bx			# calculate S
		xorl %eax, %eax				# clear eax for later use
		imul $10, %bx, %ax			# start calculating offset
		addl $1778, %eax
		imul $2, %eax				# do I need to multiply 2?
		cmp $1, %cl				# to see if it's A
		je draw_A
		cmp $2, %cl				# to see if it's C
		je draw_C
		cmp $4, %cl				# to see if it's G
		je draw_G
		cmp $8, %cl				# to see if it's T
		je draw_T
	draw_A:
		movb base_array, %cl			# put A into cl
		pushl %ebx
		pushl %edx
		call mp1_poke
		popl %edx
		popl %ebx
		movb $0, 4(%ebx, %esi)	# store A into guess
		jmp keystroke_done
	draw_C:		
		movb base_array + 1, %cl			# put C into cl
		pushl %ebx
		pushl %edx
		call mp1_poke
		popl %edx
		popl %ebx
		movb $1, 4(%ebx, %esi)	# store C into guess
		jmp keystroke_done
	draw_G:
		movb base_array + 2, %cl	# put G into cl
		pushl %ebx
		pushl %edx
		call mp1_poke
		popl %edx
		popl %ebx
		movb $2, 4(%ebx, %esi)	# store G into guess
		jmp keystroke_done
	draw_T:
		movb base_array + 3, %cl	# put T into cl
		pushl %ebx
		pushl %edx
		call mp1_poke
		popl %edx
		popl %ebx
		movb $3, 4(%ebx, %esi)	# store T into guess
		jmp keystroke_done


	keystroke_fail1:
		movl $-1, %eax				# put fail value into eax
		addl $19, %esp				# pop out all the things
		popl %edi
		popl %esi
		popl %ebx
		leave
		ret

	keystroke_done:
		movl $KA_SIZE, %ebx
		pushl %ebx
		pushl %esi					# swap the address to copy to user
		pushl 8(%ebp)
		call mp1_copy_to_user
		popl %ebx
		popl %ebx
		popl %ebx
		cmp $0, %eax				# to see if the copy fails
		jne keystroke_fail1
		addl $KA_STACK, %esp
		movl $0, %eax				# put success value into eax
		popl %edi
		popl %esi
		popl %ebx
		leave
		ret


# void mp1_ioctl_getstatus(unsigned long* user_status);
# Performs three tasks:
#	(1) show population
# 	(2) show infection
# Inputs   : unsigned long* user_status
# Outputs  : current game status
# Registers: Standard C calling convention
mp1_ioctl_getstatus:
		pushl %ebp
		movl %esp, %ebp
		pushl %ebx
		pushl %esi
		pushl %edi						# initialize setup


		subl $GS_SIZE, %esp				# leaving memory for copying
		movl %esp, %esi					# store this address in esi for later use
		movl $GS_SIZE, %eax
		movl 8(%ebp), %ebx				# move inf to ebx
		cmp $0, %ebx					# to see if there is no people
		je gt_fail
		
		movl population, %eax
		movl %eax, (%esi)				# put population into pop
		movl infection, %eax
		movl %eax, 4(%esi)			# put infection into inf
		jmp getstatus_done

	gt_fail:
		movl $-1, %eax					# return failure since people all dead
		popl %edi
		popl %esi
		popl %ebx
		leave
		ret

	getstatus_done:
		movl $GS_SIZE, %eax
		pushl %eax
		pushl %esi
		pushl %ebx
		call mp1_copy_to_user	
		popl %ebx
		popl %esi
		popl %edx		
		cmp $0, %eax					# see if copy fails
		ja gt_fail
		movl $0, %eax					# return success
		popl %edi
		popl %esi
		popl %ebx
		leave
		ret


# void mp1_ioctl_vaccinate(unsigned long packed_args);
# Performs three tasks:
#	(1) the only way to win the game
#	(2) find the correct sequence and kill the virus
# Inputs   : unsigned long packed_args
# Outputs  : kill virus
# Registers: Standard C calling convention
mp1_ioctl_vaccinate:
		pushl %ebp
		movl %esp, %ebp
		pushl %ebx
		pushl %esi
		pushl %edi							# initialize setup
		xorl %edi, %edi						# clean for counter
		xorl %edx, %edx
		xorl %eax, %eax
		xorl %ebx, %ebx
		xorl %ecx, %ecx
		xorl %esi, %esi

		movl current_board, %ebx

	vac_loop:
		call generate
		xorl %edx, %edx
		movl $100, %esi						# put the random generate number into esi
		idiv %esi							# divide random number by 100
		movw 8(%ebp), %cx					# move lower 16 bits into cx
		cmp %cx, %dx						# compare if the remainder is bigger then the probability
		jbe kill
	vac_continue:
		incl %ebx
		cmp $SCR_SIZE, %edi				# to see if it reaches the last cell
		je vaccinate_done				
		incl %edi
		jmp vac_loop
	kill:
		movb $0, %al			# store death
		movb %al, (%ebx)		# make the cell die
		jmp vac_continue


	vaccinate_done:
		xorl %ecx, %ecx
		movw 10(%ebp), %cx						# put higher 16 bits to aggression
		movl aggression, %ebx
		addl %ebx, %ecx
		movl %ecx, aggression					# put the high 16 bits into aggression
		movl $0, %eax							
		popl %edi
		popl %esi
		popl %ebx
		leave
		ret

jumptable:
		.long mp1_ioctl_startgame, mp1_ioctl_endgame, mp1_ioctl_keystroke, mp1_ioctl_getstatus, mp1_ioctl_vaccinate
