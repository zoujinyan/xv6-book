.so book.mac
.chapter CH:TRAP "Traps and system calls
.ig
	in progress
..
.PP
The x86 generates interrupts when hardware needs attention,
whether the hardware is a device or the processor itself.
An interrupts stops the normal processor loop—read an instruction,
advance the program counter, execute the instruction, repeat—and
starts executing a new sequence called an interrupt handler.
Before starting the interrupt handler, the processor saves its
previous state, so that the interrupt handler can restore that
state if appropriate.
.PP
At the end of the last chapter, we saw that programs can generate
interrupts explicitly with the
.code int
instruction, but other illegal program actions generate interrupts too:
divide by zero, attempt to access memory outside segment bounds, and so on.
These interrupts are often called exceptions.
Hardware devices use the same mechanism to get the processor's 
attention.
Although the official x86 term is interrupt, x86 refers to all
of these as traps, largely because it was the term used by
the PDP11/40 and therefore is the conventional Unix term.
This chapter uses the terms trap and interrupt interchangeably.
.PP
This chapter examines the xv6 trap handlers,
covering hardware interrupts, software exceptions,
and system calls.a
.\"
.section "Code: Hardware interrupts
.\"
Have to set up interrupt controller.
Picinit, picenable.
Interrupt masks.
Interrupt routing.
On multiprocessor, different hardware but same effect.
.\"
.section "Code: Assembly trap handlers
.\"
.PP
The x86 allows for 256 different interrupts.
Interrupts 0-31 are defined for software
exceptions, like divide errors or attempts to access invalid memory addresses.
Xv6 maps the 32 hardware interrupts to the range 32-63
and uses interrupt 64 as the system call interrupt.
On the x86, interrupt handlers are defined in the interrupt descriptor table (IDT).
The IDT has 256 entries, each giving the
.code %cs
and
.code %eip
to be used when handling the corresponding interrupt.
.code Tvinit
.line trap.c:/^tvinit/ ,
called from
.code main ,
sets up the 256 entries in the table
.code idt .
Interrupt
.code i
is handled by the
.code %eip
.code vectors[i] .
Each entry point is different, because the x86 provides
does not provide the trap number to the interrupt handler.
Using 256 different handlers is the only way to distinguish
the 256 cases.
.code Tvinit
handles
.code T_SYSCALL ,
the user system call trap,
specially: it sets the
.code XX
flag, allowing other interrupts during the system call handler,
and it sets the privilege to
.code DPL_USER ,
which allows a user program to generate
the trap with an explicit
.code int
instruction.
[[TODO: Replace SETGATE with real code.]]
.PP
The 256 different handlers must behave differently:
for some traps, the x86 pushes an extra error code on the stack,
but for most it doesn't.
The handlers for the traps without error codes
push a fake one on the stack explicitly, to make the
stack layout uniform.
Instead of writing 256 different functions by hand, we use a
Perl script
.line vectors.pl:1
to generate the entry points.  Each entry pushes an error code
if the processor didn't, pushes the interrupt number, and then
jumps to
.code alltraps ,
a common body.
.code Alltraps
.line trapasm.S:/^alltraps/
continues to save processor state: it pushes
.code %ds ,
.code %es ,
.code %fs ,
.code %gs ,
and the general-purpose registers
.lines trapasm.S:/Build.trap.frame/,/pushal/ .
The result of this effort is that the stack now contains
a
.code struct
.code trapframe 
.line x86.h:/trapframe/
describing the precise user mode processor state
at the time of the trap.
XXX picture.
The processor pushed cs, eip, and eflags.
The processor or the trap vector pushed an error number,
and alltraps pushed the rest.
The trap frame contains all the information necessary
to restore the user mode processor state
when the trap handler is done,
so that the processor can continue exactly as it was when
the trap started.
.PP
Now that the user mode processor state is saved,
.code alltraps
can set up the processor for running kernel code.
The processor set the code and stack segments
.code %cs
and
.code %ss
before entering the handler;
.code alltraps
must set
.code %ds
and
.code %es
.lines "'trapasm.S:/movw.*SEG_KDATA/,/%es/'" .
It also sets 
.code %fs
and
.code %gs
to point at the 
.code SEG_KCPU
per-CPU data segment
.lines "'trapasm.S:/movw.*SEG_KCPU/,/%gs/'" .
Chapter \*[CH:MEM] will revisit that segment.  \" TODO is CH:MEM right?
Once the segments are set properly,
.code alltraps
can call the C trap handler
.code trap .
It pushes
.code %esp,
which points at the trap frame we just constructed,
onto the stack as an argument to
.code trap
.line "'trapasm.S:/pushl.%esp/'" .
Then it calls
.code trap
.line trapasm.S:/call.trap/ .
After
.code trap 
returns,
.code alltraps
pops the argument off the stack by
adding to the stack pointer
.code trapasm.S:/addl/
and then starts executing the code at
label
.code trapret .
We traced through this code in Chapter \*[CH:MEM]
when the first user process ran it to exit to user space.
The same sequence happens here: popping through
the trap frame restores the user mode register state and then
.code iret
jumps back into user space.
.PP
The discussion so far has talked about trap saving
the user mode processor state, but traps can happen
while the kernel is executing too.  The same code runs;
the only difference is that the saved
.code %cs ,
.code %eip ,
.code %esp ,
and segment registers are all kernel values.
When the final
.code iret
restores a kernel mode 
.code %cs ,
the processor continues executing in kernel mode.
.\"
.section "Code: C trap handler
.\"
.PP
We saw in the last section that each handler sets
up a trap frame and then calls the C function
.code trap .
.code Trap
.line 'trap.c:/^trap!(/'
looks at the hardware trap number
.code tf->trapno
to decide why it has been called and what needs to be done.
If the trap is
.code T_SYSCALL ,
.code trap
calls the system call handler
.code syscall .
We'll revisit the two
.code cp->killed
checks in Chapter \*[CH:SCHED].  \" XXX really?
.PP
After checking for a system call, trap looks for hardware interrupts:
the clock (Chapter \*[CH:TRAP]),  \" XXX really?
the disk (Chapter \*[CH:DISK]),
the keyboard and serial port (Appendix \*[APP:HW]).
In addition to the expected hardware devices, a trap
can be caused by a spurious interrupt... XXX more here.
If the trap is not a system call and not a hardware device looking for
attention,
.code trap
assumes it was caused by incorect behavior (e.g.,
divide by zero) as part of the code that was executing before the trap.
If it was the kernel running, there must be a kernel bug:
.code trap
prints details about the surprise and then calls
.code panic .
.PP
[[Sidebar about panic:
panic is the kernel's last resort: the impossible has happened and the
kernel does not know how to proceed.  In xv6, panic does ...]]
.PP
If the code that caused the trap was a user program, xv6 prints
details and then sets
.code cp->killed
to kill the program.
After the trap has been handled, it is time to go back
to what was going on before the trap. 
Before doing that, 
.code trap
may exit or yield the current process; we will
look at this code more closely in Chapter \*[CH:SCHED].
.\"
.section "Code: System calls
.\"
.PP
[[XXX: Maybe start a new chapter here?]]
The last chapter ended with 
.code initcode.S
invoke a system call.
Let's look at that again.
Remember from Chapter \*[CH:MEM] that a user program
makes a system call by pushing the arguments on the
C stack and then calling a stub function that puts the
system call number in
.code %eax
and traps.
The system call numbers match the entries in the syscalls array,
a table of function pointers.
.code Syscall
.line syscall.c:/^syscall/
fetches the system call number from
.code %eax ,
checks that it is in range, and calls the function from the table.
It records that function's return value in
.code %eax .
When the trap returns to user space, it will load the values
from
.code cp->tf
into the machine registers.
Thus, when 
.code exec
returns, it will return the value
that the system call handler returned
.line "'syscall.c:/eax = syscalls/'" .
System calls conventionally return negative unmbers to indicate
errors, positive numbers for success.
If the system call number is invalid,
.code syscall
prints an error and returns \-1.
.PP
XXX system call argument checking.
Later chapters will examine the implementation of
particular system calls.
This chapter is concerned with the mechanism.
There is one bit of mechanism left: finding the system call arguments.
The helper functions argint and argptr, argstr retrieve the n'th system call
argument, as either an integer, pointer, or a string.
Argint uses the user-space esp register to locate the n'th argument:
esp points at the return address for the system cal stub.
The arguments are right above it, at esp+4.
Then the nth argument is at esp+4+4*n.  Argint calls fetchint
to read the value at that address from user memory and write it to *ip.
Fetchint cannot simply cast the address to a pointer, because kernel and user
pointers have different meaning: in the kernel,
address 0 means physical address zero, the first location in physical memory.
When a user process is executing, the kernel sets the segmentation
hardware so that user address zero corresponds to the process's private memory,
kernel address p->mem.
The kernel also uses the segmentation hardware to make sure
that the processc annot access memory outside its local private memory:
if a user program tries to read or write memory at an address of p->sz or
above, the processor will cause a segmentation trap, and trap will
kill the process, as we saw above.
Now though, the kernel is running and must implement the
memory translation and checks itself.
Fetchint checks that the user address is in range
and then convert it to a kernel pointer by adding
p->mem before reading the value.
.PP
Argptr is similar in purpose to argint: it interprets the nth system call argument
as a user pointer and sets *p to the equivalent kernel pointer.
Argptr calls argint to fetch the argument as an integer and then users
the same logic as fetchint to interpret the integer as a user pointer
and compute the equivalent kernel pointer.
Note that two translations occur during a call to argptr.
First, the user stack pointer is translated during the fetching
of the argument.
Then the argument, itself a user pointer, is translated to 
produce a kernel pointer.
.PP
Argstr is the final member of the system call argument trio.
It interprets the nth argument as a pointer, like argptr does, but then
also ensures that the pointer points at a NUL-terminated string:
the NUL must be present before the address space ends.
.PP
The system call implementations (for example, sysproc.c and sysfile.c)
are typically wrappers: they deocde the arguments using argint,
argptr, and argstr and then call the real implementations.
.PP
Let's look at how
.code sys_exec
uses these functions to get at its arguments.
.PP
XXX more here XXX
.\"
.section "Real world
.\"
interrupt handler (trap) table driven.

interrupts can move.

more complicated routing.

more system calls.

have to copy system call strings.

even harder if memory space can be adjusted.
