# LuaFAR Search: Makefile

# adjust the 3 lines below according to your configuration
PROJECT = lfsearch
path_plugin = ..
COMMON_MAK = $(path_plugin)\..\common.mak

MYOBJECTS = lfsearch.o
MYLUAOPEN_LIST = luaopen_lfsearch

T_MESSAGE = $(path_plugin)\lfsearch_message.lua
EMBED_METHOD = luasrcdiet

bootscript = $(path_plugin)\$(PROJECT).lua

scripts = \
  $(path_plugin)\_globalinfo.lua     \
  $(path_plugin)\lfs_message.lua     \
  $(path_plugin)\lfs_replib.lua      \
  $(path_plugin)\lfs_common.lua      \
  $(path_plugin)\lfs_editmain.lua    \
  $(path_plugin)\lfs_editengine.lua  \
  $(path_plugin)\lfs_mreplace.lua    \
  $(path_plugin)\lfs_rename.lua      \
  $(path_plugin)\lfs_panels.lua

modules = \
  $(path_share)*serial.lua           \
  $(path_share)*hilite.lua           \
  $(path_share)*cqueue.lua           \
  $(path_share)*far2\custommenu.lua  \
  $(path_share)*far2\dialog.lua      \
  $(path_share)*far2\history.lua     \
  $(path_share)*far2\message.lua     \
  $(path_share)*far2\tmppanel.lua    \
  $(path_share)*far2\utils.lua

FAR_EXPORTS =       \
  CLOSEPANEL        \
  CONFIGURE         \
  EXITFAR           \
  GETFINDDATA       \
  GETOPENPANELINFO  \
  OPEN              \
  PROCESSEDITOREVENT \
  PROCESSPANELEVENT \
  PROCESSPANELINPUT \
  PUTFILES          \
  SETDIRECTORY

MYCFLAGS  = -I$(PATH_LUAFARSRC) -DRUN_LUAFAR_INIT
RCFILE    = lfsearch.rc
TEMPL     = lfs_lang.templ tmpp_lang2.templ
TEMPL_SCR = lfs_lang.lua
HELP      = $(path_plugin)\lfs_eng.hlf $(path_plugin)\lfs_rus.hlf

include $(COMMON_MAK)
