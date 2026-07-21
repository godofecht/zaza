#include <juce_core/juce_core.h>
#include <juce_data_structures/juce_data_structures.h>
#include <juce_events/juce_events.h>
#include <juce_graphics/juce_graphics.h>
#include <juce_gui_basics/juce_gui_basics.h>
#include <juce_audio_basics/juce_audio_basics.h>
#include <juce_audio_devices/juce_audio_devices.h>
#include <juce_audio_formats/juce_audio_formats.h>
#include <juce_audio_processors/juce_audio_processors.h>
#include <juce_audio_utils/juce_audio_utils.h>

//==============================================================================
// Simple sine-wave synth voice
//==============================================================================
class SineWaveVoice : public juce::SynthesiserVoice
{
public:
    bool canPlaySound(juce::SynthesiserSound* sound) override
    {
        return dynamic_cast<juce::SynthesiserSound*>(sound) != nullptr;
    }

    void startNote(int midiNoteNumber, float velocity,
                   juce::SynthesiserSound*, int) override
    {
        currentAngle = 0.0;
        level = velocity * 0.25;
        tailOff = 0.0;

        auto cyclesPerSecond = juce::MidiMessage::getMidiNoteInHertz(midiNoteNumber);
        auto cyclesPerSample = cyclesPerSecond / getSampleRate();
        angleDelta = cyclesPerSample * 2.0 * juce::MathConstants<double>::pi;
    }

    void stopNote(float, bool allowTailOff) override
    {
        if (allowTailOff)
        {
            if (tailOff == 0.0)
                tailOff = 1.0;
        }
        else
        {
            clearCurrentNote();
            angleDelta = 0.0;
        }
    }

    void pitchWheelMoved(int) override {}
    void controllerMoved(int, int) override {}

    void renderNextBlock(juce::AudioSampleBuffer& outputBuffer,
                         int startSample, int numSamples) override
    {
        if (angleDelta == 0.0) return;

        if (tailOff > 0.0)
        {
            while (--numSamples >= 0)
            {
                auto currentSample = (float)(std::sin(currentAngle) * level * tailOff);

                for (auto i = outputBuffer.getNumChannels(); --i >= 0;)
                    outputBuffer.addSample(i, startSample, currentSample);

                currentAngle += angleDelta;
                ++startSample;

                tailOff *= 0.99;

                if (tailOff <= 0.005)
                {
                    clearCurrentNote();
                    angleDelta = 0.0;
                    break;
                }
            }
        }
        else
        {
            while (--numSamples >= 0)
            {
                auto currentSample = (float)(std::sin(currentAngle) * level);

                for (auto i = outputBuffer.getNumChannels(); --i >= 0;)
                    outputBuffer.addSample(i, startSample, currentSample);

                currentAngle += angleDelta;
                ++startSample;
            }
        }
    }

private:
    double currentAngle = 0.0;
    double angleDelta = 0.0;
    double level = 0.0;
    double tailOff = 0.0;
};

//==============================================================================
// Generic sound that accepts all voices
//==============================================================================
class SineWaveSound : public juce::SynthesiserSound
{
public:
    bool appliesToNote(int) override { return true; }
    bool appliesToChannel(int) override { return true; }
};

//==============================================================================
// Main synth component with on-screen piano keyboard
//==============================================================================
class SynthComponent : public juce::Component,
                       private juce::AudioIODeviceCallback,
                       private juce::MidiInputCallback,
                       private juce::MidiKeyboardStateListener
{
public:
    SynthComponent()
        : keyboardComponent(keyboardState, juce::MidiKeyboardComponent::horizontalKeyboard)
    {
        // Set up synth with 16 voices
        for (int i = 0; i < 16; ++i)
            synth.addVoice(new SineWaveVoice());

        synth.addSound(new SineWaveSound());

        // Keyboard UI
        addAndMakeVisible(keyboardComponent);
        keyboardState.addListener(this);

        // Title label
        addAndMakeVisible(titleLabel);
        titleLabel.setText("Zaza Synth — built with Zaza", juce::dontSendNotification);
        titleLabel.setFont(juce::FontOptions(24.0f).withStyle("Bold"));
        titleLabel.setJustificationType(juce::Justification::centred);
        titleLabel.setColour(juce::Label::textColourId, juce::Colours::white);

        // Status label
        addAndMakeVisible(statusLabel);
        statusLabel.setText("Play the keyboard or connect a MIDI device", juce::dontSendNotification);
        statusLabel.setFont(juce::FontOptions(14.0f));
        statusLabel.setJustificationType(juce::Justification::centred);
        statusLabel.setColour(juce::Label::textColourId, juce::Colours::lightgrey);

        // Audio device
        audioDeviceManager.initialiseWithDefaultDevices(0, 2);
        audioDeviceManager.addAudioCallback(this);
        audioDeviceManager.addMidiInputDeviceCallback({}, this);

        setSize(800, 300);
    }

    ~SynthComponent() override
    {
        audioDeviceManager.removeAudioCallback(this);
        audioDeviceManager.removeMidiInputDeviceCallback({}, this);
        keyboardState.removeListener(this);
    }

    void paint(juce::Graphics& g) override
    {
        g.fillAll(juce::Colour(0xff1a1a2e));

        // Accent bar
        g.setColour(juce::Colour(0xff16213e));
        g.fillRect(0, 0, getWidth(), 80);
    }

    void resized() override
    {
        auto area = getLocalBounds();
        auto header = area.removeFromTop(80);

        titleLabel.setBounds(header.removeFromTop(50).reduced(10, 10));
        statusLabel.setBounds(header.reduced(10, 0));

        area.removeFromTop(10);
        keyboardComponent.setBounds(area.reduced(10));
    }

    // AudioIODeviceCallback
    void audioDeviceIOCallbackWithContext(const float* const*,
                                          int,
                                          float* const* outputChannelData,
                                          int numOutputChannels,
                                          int numSamples,
                                          const juce::AudioIODeviceCallbackContext&) override
    {
        juce::AudioSampleBuffer buffer(outputChannelData, numOutputChannels, numSamples);
        buffer.clear();

        juce::MidiBuffer incomingMidi;
        keyboardState.processNextMidiBuffer(incomingMidi, 0, numSamples, true);
        synth.renderNextBlock(buffer, incomingMidi, 0, numSamples);
    }

    void audioDeviceAboutToStart(juce::AudioIODevice* device) override
    {
        synth.setCurrentPlaybackSampleRate(device->getCurrentSampleRate());
    }

    void audioDeviceStopped() override {}

    // MidiInputCallback
    void handleIncomingMidiMessage(juce::MidiInput*, const juce::MidiMessage& message) override
    {
        keyboardState.processNextMidiEvent(message);
    }

    // MidiKeyboardStateListener
    void handleNoteOn(juce::MidiKeyboardState*, int midiChannel, int midiNoteNumber, float velocity) override
    {
        juce::ignoreUnused(midiChannel, midiNoteNumber, velocity);
    }

    void handleNoteOff(juce::MidiKeyboardState*, int midiChannel, int midiNoteNumber, float) override
    {
        juce::ignoreUnused(midiChannel, midiNoteNumber);
    }

private:
    juce::AudioDeviceManager audioDeviceManager;
    juce::MidiKeyboardState keyboardState;
    juce::MidiKeyboardComponent keyboardComponent;
    juce::Synthesiser synth;

    juce::Label titleLabel;
    juce::Label statusLabel;
};

//==============================================================================
// Window
//==============================================================================
class MainWindow : public juce::DocumentWindow
{
public:
    MainWindow()
        : DocumentWindow("Zaza Synth",
                         juce::Colour(0xff1a1a2e),
                         DocumentWindow::allButtons)
    {
        setContentOwned(new SynthComponent(), true);
        setResizable(true, true);
        centreWithSize(getWidth(), getHeight());
        setVisible(true);
    }

    void closeButtonPressed() override
    {
        juce::JUCEApplication::getInstance()->systemRequestedQuit();
    }
};

//==============================================================================
// Application
//==============================================================================
class ZazaJuceApplication : public juce::JUCEApplication
{
public:
    const juce::String getApplicationName() override { return "Zaza Synth"; }
    const juce::String getApplicationVersion() override { return "1.0.0"; }

    void initialise(const juce::String&) override
    {
        mainWindow.reset(new MainWindow());
    }

    void shutdown() override
    {
        mainWindow = nullptr;
    }

private:
    std::unique_ptr<MainWindow> mainWindow;
};

START_JUCE_APPLICATION(ZazaJuceApplication)
