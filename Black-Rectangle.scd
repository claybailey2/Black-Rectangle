/*Clay Bailey
CPSC432 Spring 2020
Final Project

This code aims to implement OSC between this server and 3 smartphone clients on a LAN, each using the third tab of the "simple" layout of the TouchOSC interface, and sending accelerometer data. The OSC data will control some parameters throughout the duration of a song, composed with the Pattern classes at the end of this document.

The code runs the following operations:
1. Establish a network connection and declare how to handle the incoming OSC messages.
2. Create the sounds to be used in the song by loading samples and declaring SynthDefs.
3. Organize some event patterns to be looped and reused during the song.
4. Arrange all the sounds into a coherent song and play using a Ptpar.
*/
(
s.boot;
s.waitForBoot({
	//s.record;

	//***************************
	//***** 1. OSC MESSAGES******
	//***************************

	NetAddr.langPort.postln; //input this port number to the 'outgoing port' in TouchOSC on phone

	//For three devices: input your phone's "local ip address" as shown in TouchOSC settings.
	~grainNet = NetAddr("192.168.0.8"); // ME
	~filtNet = NetAddr("192.168.0.8");//NetAddr("192.168.0.4"); // DAD
	~strikeNet = NetAddr("192.168.0.5"); // MOM

	/*
	//for fewer devices: set the ips equal to each other as below
	~grainNet = NetAddr("192.168.0.8", 57120); // ME
	~filtNet = NetAddr("192.168.0.5", 57120); // MOM
	~strikeNet = ~grainNet; // ME
	*/

	//The user must turn on "Accelerometer" in TouchOSC settings.
	//get the incoming port numbers for each device sending accelerometer data
	OSCdef('setPort',{|msg,time,addr|
		switch (addr.ip,
			~grainNet.ip,{~grainNet.port_(addr.port)},
			~filtNet.ip,{~filtNet.port_(addr.port)},
			~strikeNet.ip,{~strikeNet.port_(addr.port)}
		);
	},'/accxyz');

	//Use this to toggle display of all incoming messages.
	//OSCFunc.trace(bool: true, hideStatusMsg: true);
	//OSCFunc.trace(false);


	//******GRAIN SYNTH CONTROLS******
	/*hold your phone so that the screen faces the sky;
	left/right tilt: grain duration
	forward/back tilt: grain trigger frequency
	screen x: tone crossfade
	screen y: volume*/

	~lr = Bus.control; ~lr.set(0);
	OSCdef('leftRight',{|msg,time,addr|
		//addr.postln;
		~lr.set(msg[1]);
	},'/accxyz',srcID: ~grainNet);

	~fb = Bus.control; ~fb.set(0);
	OSCdef('frontBack',{|msg|
		~fb.set(msg[2]);
	},'/accxyz', srcID: ~grainNet);

	~x = Bus.control; ~x.set(0.5);
	OSCdef('screenX',{|msg|
		~x.set(msg[1]);
	},'/3/xy', srcID: ~grainNet);

	~y = Bus.control; ~y.set(0.25);
	OSCdef('screenY',{|msg|
		~y.set((1 - msg[2])* -1);
	},'/3/xy', srcID: ~grainNet);


	//******FILTER CONTROLS******
	/*hold your phone so that the screen faces the sky;

	filtering the pads:
	left/right tilt: cutoff frequency
	forward/back tilt: q value

	spatializing the grain:
	screen x: panning
	screen y: distance (volume/reverb)*/
	~rq = Bus.control; ~rq.set(0);
	OSCdef('tiltQ',{|msg,time,addr|
		//addr.postln;
		~rq.set(msg[2]);
	},'/accxyz',srcID: ~filtNet);

	~f = Bus.control; ~f.set(0);
	OSCdef('tiltFreq',{|msg|
		~f.set(msg[1] * -1);
	},'/accxyz', srcID: ~filtNet);

	~pan = Bus.control; ~pan.set(0);
	~vol = Bus.control; ~vol.set(1);
	~wet = Bus.control; ~wet.set(0);

	OSCdef('spatialize',{|msg|
		var pan = msg[1].linlin(0,1,-1,1);
		var vol = msg[2].linlin(0,1,-6,0).dbamp;
		var wet = msg[2].lincurve(0,1,0.2,0.00001,-2);

		~pan.set(pan);
		~vol.set(vol);
		~wet.set(wet);
	}, '/3/xy', srcID: ~filtNet);


	//******MALLET STRIKE CONTROLS******
	/*hold your phone out so that the top faces in front of you and the screen faces your left;
	From this position, swing your phone up/down like a hammer.*/

	~calcAmp = { //set amplitude as a fxn of peak acceleration
		~finalZ
		.linlin(~zThresh,70,-5,6)
		.dbamp
		.postln;};
	~preZ = Bus.control; ~preZ.set(0);
	~zThresh = 15;//higher values will need faster downstrokes.

	OSCdef('strike',{|msg|
		//the accel has crossed the threshold in the positive direction
		if((~preZ.getSynchronous<~zThresh)
			&& (msg[3]>~zThresh), {
				r = Synth('Astab',['freq',[ 65, 70, 72, 76 , 77, 80, 82, 84 ].midicps.choose]);
				r.register;
				~finalZ = nil;
				~flag = 1;}
		);
		if(r.isRunning,{r.set('curZ',msg[3])});
		~preZ.set(msg[3]);
	},'/accxyz',srcID: ~strikeNet);

	//this message is triggered by the 'Agrain' synthdef below
	OSCFunc({|msg|
		if( (msg[3]!=0)
			&& (~flag == 1),{
				//msg.postln;
				~finalZ=msg[3]
		});
		if(~finalZ != nil, {
			r.set('t_gate',1,'amp', ~calcAmp.());
			r.isRunning_(false);
			~finalZ = nil;
			~flag = 0;
		});
	},'/tr');


	//*******************************
	//***** 2. DECLARING SOUNDS******
	//*******(SynthDefs etc.)********
	//*******************************

	t = TempoClock.default;
	t.tempo = 1.25;
	//this tempo is chosen because the accelerometer data comes in 20 times a second, which divides evenly into this beat

	//vocal sample playback
	~letsGo = Buffer.read(s, "sf/lets go.wav".resolveRelative);
	~blackRectangle = Buffer.read(s, "sf/black rectangle.wav".resolveRelative);
	SynthDef('playbuf',{|buf=0,amp=1,pan=0.3|
		Out.ar(0,Pan2.ar(PlayBuf.ar(buf.numChannels,buf,doneAction:2),pan,amp))
	}).add;

	//filter-sweeping white noise as a sound effect for accents and buildups
	SynthDef('sweep',{|tempo=1.25,gate=1,dur=4,amp=1,start = 10000, end = 100, dir| //dir=-1 down, dir=1 up
		var noise = WhiteNoise.ar();
		var freqEnv = Env([start,end],[dur],4 * dir);
		var rlpf = RLPF.ar(noise, freqEnv.kr, 0.5);
		var env = Env([0,1],[dur]);
		var envGen = EnvGen.kr(env,gate,doneAction: 2);
		var sound = Pan2.ar(rlpf,Line.kr(-0.2,0.1),envGen);
		Out.ar(0,sound*amp);
	}).add;

	//sawtooth-wave riser used for buildups
	SynthDef('sawrise',{|freq=440,dur=1,gate=1,amp=1|
		var freqEnv = EnvGen.kr(Env([freq,freq,freq*2],(dur/4)!2,3),gate);
		var env = EnvGen.kr(Env.adsr(0.1,0.001,1,0.001),gate,doneAction: 2);
		var sound = LPF.ar(Mix([Saw.ar(freqEnv),PinkNoise.ar()]),freq*4);
		Out.ar(0,Pan2.ar(sound,Line.kr(-0.5,0.1),env*amp))
	}).add;

	//same synth drums as assignment 5
	(
		~drumTune = 54;
		SynthDef('kick', {arg amp = 1, pan = 0.25;
			var bumpEnv = Env(times: [0.005, 0.005]);
			var bump = PinkNoise.ar(mul: bumpEnv.kr);
			var bodyEnv = Env(times: [0.018, 0.088]);
			var body = SinOsc.ar(~drumTune, mul: bodyEnv.kr(2));
			var mix = Mix.ar([bump * 0.3, body * 1]);
			var filt = BRF.ar(mix, 300, 0.5);
			Out.ar(0, Pan2.ar(filt * amp, pan));
		}).add;

		// PV_EvenBin in this instrument to try to chop up the sound of the snare
		SynthDef('snare',
			{arg out=0,rq = 6, vel = 1, decay = 0.25, pos = 0, amp = 1, t_gate = 1,pan=0.25;
				//pos: position hit on drum; 0 = center, 1 = rim;
				var sustain = (decay * vel).explin(0.000001, decay, decay*0.5, decay);
				var clickEnv = Env(times: [0.002, 0.002]);
				var click = WhiteNoise.ar(mul: clickEnv.kr);
				var bodyEnv = Env(times: [0.006, 0.018]);
				var bodyFreq = (~drumTune * 2.sqrt) + (pos * 100);
				var body = SinOsc.ar(bodyFreq, mul: bodyEnv.kr);
				var snareEnv = Env([4, 1]*bodyFreq*9, [sustain]);
				var snareNoise = WhiteNoise.ar;
				var snareFilt = RLPF.ar(snareNoise, snareEnv.kr, rq);
				//Chopping up the snare
				var chain = FFT(LocalBuf(1024), snareFilt, 0.5, winsize: 128);
				// adjust the winsize to change the frame size
				var even = PV_EvenBin(chain);
				var snare = IFFT(even);
				var mixEnv = EnvGen.kr(Env(times: [0.003, sustain],curve:'cub'), t_gate, doneAction:2);
				var mix = Mix.ar([click * (vel.explin(0.001,1,0.1,0.2)), body * 0.5, snare * 10]) * mixEnv;
				Out.ar(out, Pan2.ar(mix * vel * amp,pan));
		}).add;

		//the 'special' arg is the carrier:modulator frequency ratio
		SynthDef('ride',{ arg frq = 5000, special = 2.187, i = 0.8, band = 8000, cut = 12000, amp = 1, t_gate = 1,dur = 1, pan = 0.25;
			var fmpul = Pulse.ar(frq + Pulse.ar(frq * special, mul: frq * i));
			var bpf = BPF.ar(fmpul, band, 0.1);
			var benv = Env.perc(0.01,0.1);
			var henv = Env([0,1,1,0],[0.004,0.080,dur-0.084],'cub');
			var hpf = HPF.ar(fmpul, cut);
			var mix = Mix.ar([bpf*benv.kr*10, hpf*henv.kr*2]);
			var menv = EnvGen.kr(Env.perc, t_gate, doneAction: 2);
			Out.ar(0, Pan2.ar(mix*menv*amp, pan));
		}).add;
	);//end drum SynthDefs

	//an additive synth at a 0.5:1:2.02 frequency ratio. Hi-passed noise is added. Passed through a lo-pass down-sweep
	SynthDef('Alead',{|out=0,freq=440,gate=1,amp=1|
		var osc1 = SinOsc.ar(freq/2, mul: 0.4);
		var osc2 = SinOsc.ar(freq, mul: 0.2);
		var osc3 = Saw.ar(freq*2.02, mul: 0.8);
		var osc4 = HPF.ar(WhiteNoise.ar, 500, mul: 0.2);
		var add = Mix.ar([osc1,osc2,osc3,osc4]);
		var filtEnv = Env([20000,500],[t.tempo/8],-4);
		var filt = RLPF.ar(add, filtEnv.kr, 0.7);
		var ampEnv = EnvGen.kr(Env.adsr(0.005,0.005,0.5,0.5),gate,amp,doneAction: 2);
		Out.ar(out,Pan2.ar(filt,-0.25,ampEnv))
	}).add;

	//GRANULAR SYNTH
	//a custom window is used to make larger grains sound more percussive
	~env1 = Buffer.sendCollection(s, Env([0,1,0.5,0],[0.003,0.003,0.044],-3).discretize);

	//the grain input is crossfaded from a "ceramic" tone to an "organic" tone based on user input.
	//the fundamental frequency of the Klank resonator is changed dynamically.
	//A Pmono passes in  the four frequencies in the seventh chords of the harmonic progression.
	//The synth then chooses from these freqs at random each time a grain is fired.
	//freq1..freq4 are passed in as seperate arguments. I had touble using literals with the pattern classes.
	//the output is then patched into a spatializer (synthdef below)
	SynthDef('Agrain',{|outbus=0,amp=1,freq1=440,freq2=220,freq3=110,freq4=55,gate=1|
		//the grains are always tuplets.
		var trigFreq = t.tempo * ~fb.kr.linexp(-10,10,2,16).round(2);// determined by front/back tilt
		var trig = Impulse.kr(trigFreq);
		//grain duration is a fraction of time between grains
		var grainDur = trigFreq.reciprocal * ~lr.kr.linlin(-10,10,0,1);// controlled by left/right tilt
		var freqs=[freq1,freq2,freq3,freq4];
		var freq = TChoose.kr(trig,freqs*[1,2,4]);//expand the range of possible freqs by 2 octaves
		var grainIn = Array.fill(2,{|i|
			DynKlank.ar(`[
				[
					[ 1.0, 1.33875, 1.69125, 2.15375 ],//ceramic - from Klank help file
					[0.5, 1, 1.58, 2.24, 2.92, 2, 2.55, 3.16]//organic - from "Creak" effect in Farnell, Designing Sound
				][i],
				nil,
				(1..4).reciprocal.stutter(2)
			],
			[BPF.ar(PinkNoise.ar(0.07),freq,0.02),BPF.ar(PinkNoise.ar(0.07),freq,0.2)][i],//"ceramic" is less noisy
			freq,
			decayscale: 0.45//a good value found using a MouseX.kr experiment
		)});

		var snd = GrainIn.ar(2,
			trigger: trig,
			dur: grainDur,
			in: XFade2.ar(//input grain is crossfaded
				inA: grainIn[0],
				inB: grainIn[1],
				pan: ~x.kr.linlin(0,1,-1,1)),//controled with phone screen's x value
			pan: 0,
			envbufnum: ~env1,//custom window
			mul: ~y.kr*0.9//volume controlled using screen's y value
		);

		var env = EnvGen.kr(Env.asr(0.01,amp,0.01),gate,doneAction: 2);
		Out.ar(outbus,snd*env);
	}).add;

	//Spatializer
	//Uses convolution reverb and some low-passing to simulate motion through a room.
	//the position in the room is controlled by the x/y plot on the phone's screen.
	//the grain synth is routed into here.
	~irChurchFar = Buffer.read(s, "sf/st_georges_far.wav".resolveRelative);
	s.sync;
	~fftsize=2048;
	~bufsize = PartConv.calcBufSize(~fftsize, ~irChurchFar);
	~irspectrum = Buffer.alloc(s, ~bufsize, 1);
	~irspectrum.preparePartConv(~irChurchFar, ~fftsize);
	SynthDef('spatialize', {
		var sig = In.ar(12);//grain synth
		var verb = PartConv.ar(sig, ~fftsize, ~irspectrum, 0.5);
		var sound = Pan2.ar(sig, ~pan.kr(1)*0.8,~vol.kr(1))
		+ Pan2.ar(verb * ~wet.kr(1).lag(1),~pan.kr(1)*0.5,~vol.kr(1));
		var lpf = LPF.ar(sound, ~vol.kr.linexp(-30,0,20000,5000));
		//stretch goal: lpf the signal of the far ear
		//stretchy stretch goal: a doppler effect
		Out.ar(0, lpf * ~vol.kr(1))
	}).add;

	//FM Sin + Saw -> Lo-pass -> Comb
	//the modulation index is enveloped to provide the pulse
	SynthDef('Abass',{|outbus=0,gate=1,freq=110,amp=1|
		//the index's LFO provides a good quarter note pulse
		var osc1 = SinOsc.kr(freq.lag*3.02,mul: LFSaw.kr(t.tempo*2,-1.1*pi/4,freq.lag*5,freq.lag*4));
		var osc2 = SinOsc.ar(freq.lag + osc1);
		var osc3 = Saw.ar(freq.lag*2);
		var bank = Mix([osc2,osc3]);//FM Sins + Saw
		var filt = LPF.ar(bank,freq.lag*4);
		var comb = CombC.ar(filt,0.05,0.05,0.20);
		Out.ar(outbus,Pan2.ar(comb,0.1,Linen.kr(gate,0.01,amp,0.01,2,doneAction: 2)));
	}).add;

	//a strange idea for a multi-carrier fm synth i had while thinking about "just the right amount of buzz."
	//patched into a user controlled lo-pass (synthdef below)
	SynthDef('Apad',{|outbus=0,gate=1,amp=1,freq=440|
		//trial and error c:m and index
		var mod = SinOsc.ar(freq*3.01)*freq*1.5;
		//mathematically related sins: (n+1)/n, with a linearly decreasing amp
		var sins = Array.fill(3,{|i| SinOsc.ar(freq * (i+2) / (i+1) + mod) * (1 - (0.2 * i))});
		var splay = Pan2.ar(Mix.ar(sins));//pan the sins
		var filt = RLPF.ar(splay,XLine.kr(freq,freq*12));//open up a lo-pass at the start of each note
		var env = EnvGen.kr(Env.adsr(1,0.2,0.5,1),gate,1,doneAction: 2);//smooth env
		Out.ar(outbus,filt*env*amp);
	}).add;

	//user-controlled low pass filter; takes pads as input
	SynthDef('filt',{|out = 0|
		var input = In.ar(11);//i had a hard time feeding in more than one channel here.
		var lagtime = 0.03;
		Out.ar(out, Pan2.ar(
			//freqency is controlled by L/R tilt, q-value is Up/Down tilt
			RLPF.ar(input, ~f.kr.linexp(-10,10,100,3000).lag(lagtime) , ~rq.kr.linexp(-10,10,1,0.03).lag(lagtime)),
			0.15
		))
	}).add;

	//sound effect controlled by mallet strike
	//originally concieved as string ensemble playing a quick fall for disco tracks.
	//i failed to recreate that easily, so I went for a different sound, but the var names remain
	//6 saws + 2 FM Sins -> Splay -> Comb
	//this synth is instantiated and triggered by the OSCDefs in section 1
	SynthDef('Astab',{|t_gate=0,freq=700,amp=1, curZ=0|
		var fall = EnvGen.kr(Env([freq/4,freq],[0.2],4),t_gate);
		var noVol = 0.1;
		var vary = LFNoise0.kr(5,0.001,1);
		var vils = Array.fill(4,{SinOsc.ar(fall*vary)+PinkNoise.ar(noVol)});
		var cels = Array.fill(2,{SinOsc.ar(freq*vary/2)+PinkNoise.ar(noVol)});
		var via = SinOsc.ar(fall*vary)+PinkNoise.ar(noVol);
		var strings = LPF.ar((vils++cels+via).flat, freq*3);

		var brass = Array.fill(3,{
			var f = fall*vary*2;
			SinOsc.ar(f + SinOsc.kr(f*Rand(0.99,1.01),mul: f*0.25));
		});

		var sound = Splay.ar((strings++(brass*3)).flat.scramble/10,0.4,center: LFNoise0.kr(0.5,0.8));
		var decay = CombC.ar(sound,0.05,0.05,1);

		var ampEnv = EnvGen.kr(Env.perc(0.01,0.5),t_gate,doneAction: 2);
		//sends an OSC message after the peak down-ward acceleration has reached, meaning that the strike is over.
		SendTrig.kr(curZ < ~preZ.kr, 0, ~preZ.kr);
		FreeSelf.kr(DelayC.kr(Impulse.kr(1),1,1));//Memory leaks are a pain
		Out.ar(0,decay * ampEnv * amp / 1);
	}).add;

	s.sync;


	//********************************
	//***** 3. ORGANIZE PATTERNS******
	//********************************

	//chords:
	//fm, ab, eb, bb

	~beat1 = Ppar([
		Pbind('instrument','ride','dur',Pseq([1]),'special',3.142,'amp',0.05),
		Pseq([Pbind('instrument','kick','dur',Pseq((1!3)++(0.5!2)/2),'amp',0.5)],7),
		Pseq([Pbind('instrument','ride',
			'dur',Pseq((([Rest(1/4),1/8,Rest(1/8)]!3)++[Rest(1/4),1/4]).flat),
			'special',Pseq(((([Rest(),2.187,Rest()]!3)++[Rest(),1])).flat),
			'amp',Pseq((([Rest(),0.1,Rest()]!3)++[Rest(),0.2]).flat))],7),
	]);
	~gp = Pmono('Agrain','outbus',12,'amp',0.6,'dur',2,
		'freq1',Pseq([51,63,50,50].midicps,inf),
		'freq2',Pseq([53,55,51,53].midicps,inf),
		'freq3',Pseq([60,60,58,58].midicps,inf),
		'freq4',Pseq([56,56,67,56].midicps,2)
	);
	~bass = Pmono('Abass','octave',2,'root',-4,'legato',1,'amp',0.5,
		'dur',Pseq((([3,1]!3)++[2,1,1]).flat/2,inf),
		'degree',Pseq([-2,-5,0,2,-3,4,1,0,-1],2)
	);
	~pad = Pbind('instrument','Apad',
		'octave',5,'root',-4,'outbus',11,'amp',0.025,'dur',Pseq([2],inf),
		'note',Pseq([[-3,0,4],[-5,0,4],[-5,-1,2],[-3,2,6]],2));
	~beat2 = Ppar([
		Pbind('instrument','ride','dur',Pseq([1]),'special',5.179,'amp',0.05),
		Pseq([Pbind('instrument','kick','dur',Pseq((1!3)++(0.5!2)/2),'amp',0.5)],7),
		Pbind('instrument','snare',
			'amp',0.2,
			'dur',Pseq([Rest(1),1,Rest(1),1]/2,7)),
		Pseq([Pbind('instrument','ride',
			'dur',    Pseq((( [Rest(1/4),1/8,1/8]!3)++[Rest(1/4),1/4]).flat),
			'special',Pseq(((([Rest(),2.187,2.187]!3)    ++[Rest(),1])).flat),
			'amp'    ,Pseq((( [Rest(),0.1,0.05]!3)      ++[Rest(),0.2]).flat))],7),
	]);
	~beat3 = Ppar([
		Pbind('instrument','ride','dur',Pseq([1]),'special',4.444,'amp',0.05),
		Pseq([Pbind('instrument','kick','dur',Pseq((1!3)++(0.5!2)/2),'amp',0.5)],7),
		Pbind('instrument','snare',
			'amp',0.2,
			'dur',Pseq([Rest(1),1,Rest(1),0.75,0.25]/2,7)),
		Pseq([Pbind('instrument','ride',
			'dur',    Pseq((( [Rest(1/4),1/8,1/8]!4)).flat,inf),
			'special',Pseq((([Rest(),2.187,2.187]!4)).flat,inf),
			'amp'    ,Pseq((([Rest(),0.05,0.025]!4).flat),7))
		])
	]);
	~aMelo = Pbind('instrument','Alead','octave',6,'root',-4,
		'dur',Pseq([1,1,1/2,1/2,1/2,1,1,1,1/2,1/2,1/2]/2,inf),
		'degree',Pseq([-2,0,0,0,4,2,2,2,2,1,2,1,1,1,1,2,1,1,1,-2,0,-1],2));

	//Start up the FX synths before playing
	Synth('spatialize');
	Synth('filt');

	/*
	//DEMO (which didn't work in class...)

	Ppar([
	~beat3,
	~gp,
	Pbindf(~bass,'outbus',0),//no filt,
	Pbindf(~pad,'amp',(0.025))
	],inf).play;
	*/

	//***************************
	//***** 4. ARRANGE SONG******
	//***************************
	Ptpar([
		//intro
		0,Pbind('instrument','ride','dur',0.125,'amp',Pseq((((31..0)-45).dbamp))),
		0,Pbind('instrument','sweep','dur',Pseq([4]),'amp',0.1,'start',10000,'end',100,'dir',-1),
		2*2,Pbind('instrument','sweep','dur',Pseq([3]),'amp',0.1,'start',100,'end',10000,'dir',1),
		2*2,Pbind('instrument','sawrise','dur',Pseq([1/2],inf),'note',Pseq((0..6)),'legato',1,'amp',Pseq((-24..-18).dbamp)),
		3*2+1.5,Pbind('instrument','playbuf','buf',~letsGo,'amp',Pseq([0.15])),

		4*2,~beat1,
		4*2,~gp,
		11*2+1,Pbind('instrument','playbuf','buf',~blackRectangle,'amp',Pseq([0.35])),

		12*2,~beat2,
		12*2,~gp,
		12*2,Pbindf(~bass,'outbus',0),//no filt: i used to route these into 'filt'

		18*2,Pbind('instrument','sweep','dur',Pseq([3]),'amp',0.1,'start',100,'end',10000,'dir',1),

		20*2,~beat3,
		20*2,~gp,
		20*2,Pbindf(~bass,'outbus',0),
		20*2,Pbind('instrument','Apad',
			'octave',5,'root',-4,'outbus',11,'amp',0.025,'dur',Pseq([2],inf),
			'note',Pseq([[-3,0,4],[-5,0,4],[-5,-1,2],[-3,2,6]],2)),

		26*2,Pbind('instrument','sawrise','dur',Pseq([1/2],inf),'note',Pseq((0..7)),'legato',1,'amp',Pseq((-24..-16).dbamp)),
		28*2,Pbind('instrument','sweep','dur',Pseq([4]),'amp',0.1,'start',10000,'end',100,'dir',-1),
		28*2,~beat3,
		28*2,~gp,
		28*2,Pbindf(~bass,'outbus',0),
		28*2,Pbind('instrument','Apad',
			'octave',5,'root',-4,'outbus',11,'amp',0.025,'dur',Pseq([2],inf),
			'note',Pseq([[-3,0,4],[-5,0,4],[-5,-1,2],[-3,2,6]],2)),
		28*2,~aMelo,

		36*2,~beat3,
		36*2,~gp,
		36*2,Pbindf(~bass,'outbus',0),
		36*2,~pad,
		36*2,~aMelo,
		43*2+1.5,Pbind('instrument','playbuf','buf',~letsGo,'amp',Pseq([0.15])),

		44*2,Pbind('instrument','sweep','dur',Pseq([4]),'amp',0.1,'start',10000,'end',100,'dir',-1),
		44*2,~pad,

		52*2,~pad,
		52*2,Pbind('instrument','ride','dur',Pseq([1,1,1,1/4,Rest(1/4),(1/16!8)].flat / 2, 8),'amp',0.01),

		60*2,~beat1,
		60*2,~gp,
		66*2,Pbind('instrument','sawrise','dur',Pseq([1/2],inf),'note',Pseq((0..7)),'legato',1,'amp',Pseq((-24..-16).dbamp)),
		67*2+1,Pbind('instrument','playbuf','buf',~blackRectangle,'amp',Pseq([0.35])),

		68*2,Pbind('instrument','sweep','dur',Pseq([4]),'amp',0.1,'start',10000,'end',100,'dir',-1),
		68*2,~beat3,
		68*2,~gp,
		68*2,Pbindf(~bass,'outbus',0),
		68*2,~pad,
		68*2,~aMelo,

		76*2,~beat3,
		76*2,~gp,
		76*2,Pbindf(~bass,'outbus',0),
		76*2,~pad,
		76*2,~aMelo,
		83*2+1.5,Pbind('instrument','playbuf','buf',~letsGo,'amp',Pseq([0.15])),
		//outro dc al fine
		84*2,Pbind('instrument','ride','dur',0.125,'amp',Pseq((((31..0)-50).dbamp))),
		84*2,Pbind('instrument','sweep','dur',Pseq([4]),'amp',0.1,'start',10000,'end',100,'dir',-1),
		86*2,Pbind('instrument','sweep','dur',Pseq([3]),'amp',0.1,'start',100,'end',10000,'dir',1),
		86*2,Pbind('instrument','sawrise','dur',Pseq([1/2],inf),'note',Pseq((0..6)),'legato',1,'amp',Pseq((-24..-18).dbamp)),
		87*2+1,Pbind('instrument','playbuf','buf',~blackRectangle,'amp',Pseq([0.35])),
	]).play;
	/**/
});
)