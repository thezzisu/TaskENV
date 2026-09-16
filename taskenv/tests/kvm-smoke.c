#include <linux/kvm.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#define CHECK(x) do { if ((x)<0) { perror(#x); exit(1); } } while(0)
int main(void) {
 int kvm=open("/dev/kvm",O_RDWR|O_CLOEXEC); CHECK(kvm);
 if(ioctl(kvm,KVM_GET_API_VERSION,0)!=12) return 2;
 int vm=ioctl(kvm,KVM_CREATE_VM,0); CHECK(vm);
 unsigned char *mem=mmap(NULL,4096,PROT_READ|PROT_WRITE,MAP_PRIVATE|MAP_ANONYMOUS,-1,0);
 if(mem==MAP_FAILED) return 3;
 /* 16-bit real-mode guest: mov ax,42; hlt */
 unsigned char code[]={0xb8,0x2a,0x00,0xf4}; memcpy(mem,code,sizeof(code));
 struct kvm_userspace_memory_region region={.slot=0,.guest_phys_addr=0,.memory_size=4096,.userspace_addr=(unsigned long)mem};
 CHECK(ioctl(vm,KVM_SET_USER_MEMORY_REGION,&region));
 int vcpu=ioctl(vm,KVM_CREATE_VCPU,0); CHECK(vcpu);
 struct kvm_sregs s; CHECK(ioctl(vcpu,KVM_GET_SREGS,&s)); s.cs.base=0;s.cs.selector=0;CHECK(ioctl(vcpu,KVM_SET_SREGS,&s));
 struct kvm_regs r={.rip=0,.rflags=2};CHECK(ioctl(vcpu,KVM_SET_REGS,&r));
 int size=ioctl(kvm,KVM_GET_VCPU_MMAP_SIZE,0);CHECK(size);
 struct kvm_run *run=mmap(NULL,size,PROT_READ|PROT_WRITE,MAP_SHARED,vcpu,0);if(run==MAP_FAILED)return 4;
 CHECK(ioctl(vcpu,KVM_RUN,0));CHECK(ioctl(vcpu,KVM_GET_REGS,&r));
 printf("KVM_RUN exit=%u RAX=%llu\n",run->exit_reason,(unsigned long long)r.rax);
 return run->exit_reason==KVM_EXIT_HLT && r.rax==42 ? 0 : 5;
}
