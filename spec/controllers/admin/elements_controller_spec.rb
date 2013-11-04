require 'spec_helper'

module Alchemy
  describe Admin::ElementsController do
    let(:alchemy_page) { create(:page) }
    let(:element) { FactoryGirl.create(:element, :page_id => alchemy_page.id) }
    let(:element_in_clipboard) { FactoryGirl.create(:element, :page_id => alchemy_page.id) }
    let(:clipboard) { session[:clipboard] = Clipboard.new }

    before { sign_in(author_user) }

    describe '#new' do
      let(:alchemy_page) { build_stubbed(:page) }
      before { Page.stub(:find_by_id).and_return(alchemy_page) }

      it "assign variable for all available element definitions" do
        alchemy_page.should_receive(:available_element_definitions)
        get :new, {page_id: alchemy_page.id}
      end

      context "with elements in clipboard" do
        let(:clipboard_items) { [{:id => element.id, :action => 'copy'}] }

        before { clipboard[:elements] = clipboard_items }

        it "should load all elements from clipboard" do
          Element.should_receive(:all_from_clipboard_for_page).and_return(clipboard_items)
          get :new, {page_id: alchemy_page.id}
          assigns(:clipboard_items).should == clipboard_items
        end
      end
    end

    describe '#create' do
      describe 'insertion position' do
        let(:alchemy_page) { create(:page) }
        before { element }

        it "should insert the element at bottom of list" do
          post :create, {element: {name: 'news', page_id: alchemy_page.id}}
          alchemy_page.elements.count.should == 2
          alchemy_page.elements.last.name.should == 'news'
        end

        context "on a page with a setting for insert_elements_at of top" do
          before do
            PageLayout.stub(:get).and_return({
              'name' => 'news',
              'elements' => ['news'],
              'insert_elements_at' => 'top'
            })
          end

          it "should insert the element at top of list" do
            post :create, {:element => {:name => 'news', :page_id => alchemy_page.id}, :format => :js}
            alchemy_page.elements.count.should == 2
            alchemy_page.elements.first.name.should == 'news'
          end
        end
      end

      context "if page has cells" do
        context "" do
          before do
            @page = FactoryGirl.create(:public_page, :do_not_autogenerate => false)
            @cell = FactoryGirl.create(:cell, :name => 'header', :page => @page)
            PageLayout.stub(:get).and_return({
              'name' => 'standard',
              'elements' => ['article'],
              'cells' => ['header']
            })
            Cell.stub(:definition_for).and_return({'name' => 'header', 'elements' => ['article']})
          end

          context "and cell name in element name" do
            it "should put the element in the correct cell" do
              post :create, {:element => {:name => "article#header", :page_id => @page.id}, :format => :js}
              @cell.elements.first.should be_an_instance_of(Element)
            end
          end

          context "and no cell name in element name" do
            it "should put the element in the main cell" do
              post :create, {:element => {:name => "article", :page_id => @page.id}, :format => :js}
              @page.elements.not_in_cell.first.should be_an_instance_of(Element)
            end
          end
        end

        context "with paste_from_clipboard in parameters" do
          context "" do
            before do
              @page = FactoryGirl.create(:public_page, :do_not_autogenerate => false)
              @cell = FactoryGirl.create(:cell, :name => 'header', :page => @page)
              PageLayout.stub(:get).and_return({
                'name' => 'standard',
                'elements' => ['article'],
                'cells' => ['header']
              })
              Cell.stub(:definition_for).and_return({'name' => 'header', 'elements' => ['article']})
              clipboard[:elements] = [{:id => element_in_clipboard.id}]
            end

            context "and cell name in element name" do
              it "should create the element in the correct cell" do
                post :create, {:element => {:page_id => @page.id}, :paste_from_clipboard => "#{element_in_clipboard.id}##{@cell.name}", :format => :js}
                @cell.elements.first.should be_an_instance_of(Element)
              end
            end

            context "and no cell name in element name" do
              it "should create the element in the nil cell" do
                post :create, {:element => {:page_id => @page.id}, :paste_from_clipboard => "#{element_in_clipboard.id}", :format => :js}
                @page.elements.first.cell.should == nil
              end
            end

            context "" do
              before { @cell.elements.create(:page_id => @page.id, :name => "article", :create_contents_after_create => false) }

              it "should set the correct position for the element" do
                post :create, {:element => {:page_id => @page.id}, :paste_from_clipboard => "#{element_in_clipboard.id}##{@cell.name}", :format => :js}
                @cell.elements.last.position.should == @cell.elements.count
              end
            end
          end

          context "on a page with a setting for insert_elements_at of top" do
            let(:alchemy_page)                 { FactoryGirl.create(:public_page, :name => 'News') }
            let(:element_in_clipboard) { FactoryGirl.create(:element, :page => alchemy_page, :name => 'news') }
            let(:cell)                 { alchemy_page.cells.first }
            let(:element)              { FactoryGirl.create(:element, :name => 'news', :page => alchemy_page, :cell => cell) }

            before do
              PageLayout.stub(:get).and_return({
                'name' => 'news',
                'elements' => ['news'],
                'insert_elements_at' => 'top',
                'cells' => ['news']
              })
              Cell.stub(:definition_for).and_return({'name' => 'news', 'elements' => ['news']})
              clipboard[:elements] = [{:id => element_in_clipboard.id}]
              cell.elements << element
            end

            it "should insert the element at top of list" do
              post :create, {:element => {:name => 'news', :page_id => alchemy_page.id}, :paste_from_clipboard => "#{element_in_clipboard.id}##{cell.name}", :format => :js}
              cell.elements.count.should == 2
              cell.elements.first.name.should == 'news'
              cell.elements.first.should_not == element
            end
          end
        end
      end

      context "with paste_from_clipboard in parameters" do
        render_views

        before do
          clipboard[:elements] = [{:id => element_in_clipboard.id, :action => 'cut'}]
        end

        it "should create an element from clipboard" do
          post :create, {:paste_from_clipboard => element_in_clipboard.id, :element => {:page_id => alchemy_page.id}, :format => :js}
          response.status.should == 200
          response.body.should match(/Succesfully added new element/)
        end

        context "and with cut as action parameter" do
          it "should also remove the element id from clipboard" do
            post :create, {:paste_from_clipboard => element_in_clipboard.id, :element => {:page_id => alchemy_page.id}, :format => :js}
            session[:clipboard].contains?(:elements, element_in_clipboard.id).should_not be_true
          end
        end
      end
    end

    describe '#find_or_create_cell' do
      before do
        Cell.stub(:definition_for).and_return({'name' => 'header', 'elements' => ['header']})
        controller.instance_variable_set(:@page, alchemy_page)
      end

      context "with element name and cell name in the params" do
        before do
          controller.stub(:params).and_return({
            :element => {:name => 'header#header'}
          })
        end
        context "with cell not existing" do
          it "should create the cell" do
            expect {
              controller.send(:find_or_create_cell)
            }.to change(alchemy_page.cells, :count).from(0).to(1)
          end
        end

        context "with the cell already present" do
          before { FactoryGirl.create(:cell, :page => alchemy_page, :name => 'header') }

          it "should load the cell" do
            expect {
              controller.send(:find_or_create_cell)
            }.to_not change(alchemy_page.cells, :count)
          end
        end
      end

      context "with only the element name in the params" do
        before do
          controller.stub(:params).and_return({
            :element => {:name => 'header'}
          })
        end

        it "should return nil" do
          controller.send(:find_or_create_cell).should be_nil
        end
      end
    end

    describe '#update' do
      let(:page)    { build_stubbed(:page) }
      let(:element) { build_stubbed(:element, page: page) }
      let(:contents_parameters) { ActionController::Parameters.new(1 => {ingredient: 'Title'}) }
      let(:element_parameters) { ActionController::Parameters.new(tag_list: 'Tag 1', public: false) }

      before do
        Element.stub(:find).and_return element
        controller.should_receive(:contents_params).and_return(contents_parameters)
      end

      it "updates all contents in element" do
        element.should_receive(:update_contents).with(contents_parameters)
        put :update, {id: element.id}
      end

      it "updates the element" do
        controller.should_receive(:element_params).and_return(element_parameters)
        element.should_receive(:update_contents).and_return(true)
        element.should_receive(:update_attributes!).with(element_parameters)
        put :update, {id: element.id}
      end

      it "updates timestamps of page" do
        element.should_receive(:update_contents).and_return(true)
        page.should_receive(:touch)
        put :update, {id: element.id}
      end

      context 'with to_be_sweeped_pages' do
        let(:page_1) { build_stubbed(:page) }
        let(:page_2) { build_stubbed(:page) }

        it "updates timestamps of page" do
          element.should_receive(:update_contents).and_return(true)
          element.should_receive(:to_be_sweeped_pages).and_return([page_1, page_2])
          page_1.should_receive(:touch)
          page_2.should_receive(:touch)
          put :update, {id: element.id}
        end
      end

      context "failed validations" do
        it "displays validation failed notice" do
          element.should_receive(:update_contents).and_return(false)
          put :update, {id: element.id}
          assigns(:element_validated).should be_false
        end
      end
    end

    describe 'params security' do
      context "contents params" do
        let(:parameters) { ActionController::Parameters.new(contents: {1 => {ingredient: 'Title'}}) }

        specify ":contents is required" do
          controller.params.should_receive(:require).with(:contents).and_return(parameters)
          controller.send :contents_params
        end

        specify "everything is permitted" do
          controller.should_receive(:params).and_return(parameters)
          parameters.should_receive(:require).with(:contents).and_return(parameters)
          parameters.should_receive(:permit!)
          controller.send :contents_params
        end
      end

      context "element params" do
        let(:parameters) { ActionController::Parameters.new(element: {public: true}) }

        specify ":element is required" do
          controller.params.should_receive(:require).with(:element).and_return(parameters)
          controller.send :element_params
        end

        specify ":public and :tag_list is permitted" do
          controller.should_receive(:params).and_return(parameters)
          parameters.should_receive(:require).with(:element).and_return(parameters)
          parameters.should_receive(:permit).with(:public, :tag_list)
          controller.send :element_params
        end
      end
    end

    describe '#list' do
      render_views

      it "should return a select tag with elements" do
        Alchemy::Page.should_receive(:find_by_urlname_and_language_id).and_return(alchemy_page)
        Alchemy::Element.stub_chain([:published, :where]).and_return([element])
        get :list, {:page_urlname => alchemy_page.urlname, :format => :js}
        response.body.should match(/select(.*)elements_from_page_selector(.*)option/)
      end
    end

    describe "untrashing" do
      before do
        @element = FactoryGirl.create(:element, :public => false, :position => nil, :page_id => 58, :cell_id => 32)
        # Because of a before_create filter it can not be created with a nil position and needs to be trashed here
        @element.trash!
      end

      it "should set a new position to the element" do
        post :order, {:element_ids => ["#{@element.id}"], :format => :js}
        @element.reload
        @element.position.should_not == nil
      end

      it "should assign the (new) page_id to the element" do
        post :order, {:element_ids => ["#{@element.id}"], :page_id => 1, :cell_id => nil, :format => :js}
        @element.reload
        @element.page_id.should == 1
      end

      it "should assign the (new) cell_id to the element" do
        post :order, {:element_ids => ["#{@element.id}"], :page_id => 1, :cell_id => 5, :format => :js}
        @element.reload
        @element.cell_id.should == 5
      end
    end
  end
end
