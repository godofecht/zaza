#include <juce_core/juce_core.h>
#include <juce_data_structures/juce_data_structures.h>
#include <juce_events/juce_events.h>
#include <juce_graphics/juce_graphics.h>
#include <juce_gui_basics/juce_gui_basics.h>

class MainComponent : public juce::Component
{
public:
    MainComponent()
    {
        setSize(600, 400);
        addAndMakeVisible(button);
        button.setButtonText("Click Me!");
        button.onClick = [this]() { 
            button.setButtonText("Thanks!");
        };
    }

    void paint(juce::Graphics& g) override
    {
        g.fillAll(juce::Colours::darkgrey);
        g.setColour(juce::Colours::white);
        g.setFont(20.0f);
        g.drawText("Hello from JUCE!", getLocalBounds(), juce::Justification::centred);
    }

    void resized() override
    {
        auto bounds = getLocalBounds();
        button.setBounds(bounds.removeFromBottom(50).reduced(200, 10));
    }

private:
    juce::TextButton button;
};

class MainWindow : public juce::DocumentWindow
{
public:
    MainWindow() 
        : DocumentWindow("JUCE Example", 
                        juce::Colours::darkgrey,
                        DocumentWindow::allButtons)
    {
        setContentOwned(new MainComponent(), true);
        setResizable(true, true);
        centreWithSize(getWidth(), getHeight());
        setVisible(true);
    }

    void closeButtonPressed() override
    {
        juce::JUCEApplication::getInstance()->systemRequestedQuit();
    }
};

class JuceExampleApplication : public juce::JUCEApplication
{
public:
    const juce::String getApplicationName() override { return "JUCE Example"; }
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

START_JUCE_APPLICATION(JuceExampleApplication) 