#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
#include <string.h>
#define API __declspec(dllexport)
struct info { const char *name, *version, *extensions; bool fullpath, blockextract; };
struct game { const char *path; const void *data; size_t size; const char *meta; };
struct geometry { unsigned w,h,mw,mh; float aspect; };
struct timing { double fps, rate; };
struct av { struct geometry geometry; struct timing timing; };
static bool (*environment)(unsigned,void*);
static void (*video)(const void*,unsigned,unsigned,size_t);
static size_t (*audio_batch)(const int16_t*,size_t);
static int16_t (*input)(unsigned,unsigned,unsigned,unsigned);
static const uint8_t *rom;
static uint8_t sram[8];
API void retro_set_environment(bool (*fn)(unsigned,void*)) { environment=fn; }
API void retro_set_video_refresh(void (*fn)(const void*,unsigned,unsigned,size_t)) { video=fn; }
API void retro_set_audio_sample(void (*fn)(int16_t,int16_t)) { (void)fn; }
API void retro_set_audio_sample_batch(size_t (*fn)(const int16_t*,size_t)) { audio_batch=fn; }
API void retro_set_input_poll(void (*fn)(void)) { (void)fn; }
API void retro_set_input_state(int16_t (*fn)(unsigned,unsigned,unsigned,unsigned)) { input=fn; }
API void retro_init(void) { memset(sram,0,sizeof(sram)); }
API void retro_deinit(void) {}
API void retro_get_system_info(struct info *i) { *i=(struct info){"fixture","1","nes",false,false}; }
API void retro_get_system_av_info(struct av *i) { *i=(struct av){{2,1,2,1,2.0f},{50.0,48000.0}}; }
API bool retro_load_game(const struct game *g) {
 const char *bios=0,*saves=0; int format=1;
 if(!environment(9,&bios)||!environment(31,&saves)||!bios||!saves) return false;
 if(!environment(10,&format)||!g||!g->data||g->size<1) return false;
 rom=(const uint8_t*)g->data; return true;
}
API void retro_unload_game(void) { rom=0; }
API void retro_run(void) {
 const uint32_t pixels[2]={0x00ff0000,0x0000ff00};
 const int16_t samples[4]={100,-100,200,-200};
 sram[0]=rom[0]; sram[1]=(uint8_t)input(1,1,0,8);
 video(pixels,2,1,sizeof(pixels)); audio_batch(samples,2);
}
API void *retro_get_memory_data(unsigned id) { return id==0?sram:0; }
API size_t retro_get_memory_size(unsigned id) { return id==0?sizeof(sram):0; }
API size_t retro_serialize_size(void) { return sizeof(sram); }
API bool retro_serialize(void *data,size_t size) { if(size!=sizeof(sram))return false; memcpy(data,sram,size);return true; }
API bool retro_unserialize(const void *data,size_t size) { if(size!=sizeof(sram))return false;memcpy(sram,data,size);return true; }
