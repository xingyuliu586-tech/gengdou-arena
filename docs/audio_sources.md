# 音频来源与制作

| 文件 | 来源/制作方法 | 用途 |
| --- | --- | --- |
| `assets/audio/niulai_ultimate.wav` | 用户提供 `牛来.mp4` 的开头 6.0 秒音轨，单声道 44.1 kHz，轻度高低通、响度整理及末尾 0.2 秒淡出 | 牛来大招 |
| `assets/audio/naiwa_ultimate.wav` | 用户提供 `奶蛙.mp4` 的开头 5.0 秒音轨，同样处理 | 奶蛙大招 |
| `assets/audio/daishu_ultimate.wav` | 用户提供 `美团袋鼠3s.mp4` 的开头 3.0 秒音轨，单声道 44.1 kHz，轻度高低通、响度整理及末尾 0.2 秒淡出 | 袋鼠大招 |
| `assets/audio/attack_swing.wav` | 原创噪声扫频与正弦波合成 | 出招破风声，四个角色以不同音高播放 |
| `assets/audio/attack_hit.wav` | 原创低频鼓点与噪声合成 | 攻击命中 |
| `assets/audio/hurt.wav` | 原创调制合成音 | 受击反馈 |
| `assets/audio/block.wav` | 原创金属调制音 | 防御反馈 |
| `assets/audio/skill.wav` | 原创上行扫频合成音 | 技能起手 |
| `assets/audio/battle_theme.wav` | 用户提供 `c75299a40674212200113f470cf0862b.mp4` 的完整约 18.13 秒音轨；首尾交叠 0.45 秒以减轻循环接缝，实际循环约 17.69 秒；游戏内以较低音量播放 | 标题与战斗背景音乐 |

四段用户视频的完整原文件不随项目打包；项目仅包含提取的音轨。原创普通音效的生成脚本保留在项目 `tools/generate_sfx.py`；`tools/generate_bgm.py` 是上一版背景音乐的备选生成脚本。Godot 通过 `AudioStreamPlayer` 循环播放当前背景音轨，代码显式设置 WAV 循环终点为音轨的采样帧数，避免播放器启动后立刻停止；角色大招音频播放期间背景音乐自动降低音量。

