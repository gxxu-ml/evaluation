#!/usr/bin/evn bash

mkdir -p $HOME/bin
mkdir -p $HOME/opt

mkdir -p $HOME/opt/just
cd $HOME/opt/just
curl -LO https://github.com/casey/just/releases/download/1.25.0/just-1.25.0-x86_64-unknown-linux-musl.tar.gz
tar -xzvf just-1.25.0-x86_64-unknown-linux-musl.tar.gz --no-same-owner
ln -s $HOME/opt/just/just $HOME/bin/just

echo "export PATH=\$PATH:\$HOME/bin" >> $HOME/.bashrc

touch $HOME/.tmux.conf
echo "set -g mouse on" >> $HOME/.tmux.conf
echo "set-option -g default-shell /usr/bin/fish" >> $HOME/.tmux.conf

mkdir -p $HOME/.config/fish
touch $HOME/.config/fish/config.fish
echo "fish_vi_key_bindings" >> $HOME/.config/fish/config.fish
mkdir -p $HOME/.config/fish/completions
$HOME/bin/just --completions fish > $HOME/.config/fish/completions/just.fish

mkdir -p $HOME/tmp
curl https://raw.githubusercontent.com/oh-my-fish/oh-my-fish/master/bin/install > $HOME/tmp/omf-install
fish $HOME/tmp/omf-install --noninteractive --yes
fish -c "omf install https://github.com/jhillyerd/plugin-git"
fish -c "omf install https://github.com/jethrokuan/fzf"

rm -r $HOME/DeepSpeedExamples/applications/DeepSpeed-Chat/dschat
ln -s $HOME/lvllm/deepspeed/dschat $HOME/DeepSpeedExamples/applications/DeepSpeed-Chat/dschat
mkdir -p $HOME/lvllm/deepspeed/data
ln -s /new_data/experiments/xuk/formatted_data $HOME/lvllm/deepspeed/data/Labrador

/root/dschat/bin/pip install wandb fire

# /root/fsdp/bin/pip install wandb fire
# /root/fsdp/bin/pip install -r $HOME/lvllm/fsdp/requirements.txt